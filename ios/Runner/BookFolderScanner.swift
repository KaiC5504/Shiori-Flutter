import Foundation

/// Per-format byte limits; keep in step with `localBookByteLimit` in
/// lib/book_import_limits.dart.
enum BookImportFormatPolicy {
  static let extensions: Set<String> = ["txt", "epub", "mobi", "azw", "azw3", "prc", "fb2", "pdf", "docx",
    "rtf", "html", "htm", "xhtml", "md", "markdown", "zip"]

  static func byteLimit(_ pathExtension: String) -> Int {
    switch pathExtension.lowercased() {
    case "zip", "epub", "pdf", "docx": return 512 * 1024 * 1024
    case "mobi", "azw", "azw3", "prc": return 256 * 1024 * 1024
    case "html", "htm", "xhtml", "md", "markdown": return 32 * 1024 * 1024
    default: return 128 * 1024 * 1024
    }
  }
}

/// Watches one user-granted folder (or the App's own Documents, visible in
/// Files) for books. A file is offered again only when its size or
/// modification date changes, so deleting a book from the library sticks.
final class BookFolderScanner {
  private struct State: Codable {
    var bookmark: Data?
    var appDocuments = false
    var name = ""
    var automatic = true
    var extensions: [String]?
    var imported: [String: String] = [:]
  }

  private struct Entry { let url: URL; let relative: String; let signature: String; let name: String }

  private static let maximumBooks = 2000
  private let stateFile: URL
  private let documentsDirectory: URL
  private let files = FileManager.default
  private var state: State
  private var entries: [String: Entry] = [:]
  private var scope: URL?

  init(stateFile: URL, documentsDirectory: URL) throws {
    self.stateFile = stateFile
    self.documentsDirectory = documentsDirectory
    try files.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    if let data = try? Data(contentsOf: stateFile), let saved = try? JSONDecoder().decode(State.self, from: data) {
      state = saved
    } else {
      state = State()
    }
  }

  func info() throws -> [String: Any]? {
    guard state.appDocuments || state.bookmark != nil else { return nil }
    let readable: Bool
    if let root = try? resolve() {
      let scoped = !state.appDocuments && root.startAccessingSecurityScopedResource()
      defer { if scoped { root.stopAccessingSecurityScopedResource() } }
      readable = files.isReadableFile(atPath: root.path)
    } else {
      readable = false
    }
    return ["name": state.name, "automatic": state.automatic, "readable": readable, "all": state.appDocuments]
  }

  func select(_ folder: URL) throws -> [String: Any]? {
    let scoped = folder.startAccessingSecurityScopedResource()
    defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
    let bookmark = try folder.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    finishAccess()
    let previous = state
    state = State(bookmark: bookmark, appDocuments: false, name: folder.lastPathComponent,
      automatic: previous.automatic, extensions: previous.extensions,
      imported: !previous.appDocuments && previous.name == folder.lastPathComponent ? previous.imported : [:])
    try save()
    return try info()
  }

  func selectApplicationDocuments() throws -> [String: Any]? {
    finishAccess()
    let previous = state
    state = State(bookmark: nil, appDocuments: true, name: "Shiori", automatic: previous.automatic,
      extensions: previous.extensions, imported: previous.appDocuments ? previous.imported : [:])
    try save()
    return try info()
  }

  func formats() throws -> [String] { state.extensions ?? BookImportFormatPolicy.extensions.sorted() }

  func setFormats(_ values: [String]) throws {
    let allowed = Set(values.map { $0.lowercased() }).intersection(BookImportFormatPolicy.extensions)
    guard !allowed.isEmpty else { throw BookDocumentFailure(code: "scan_formats", message: "至少保留一种格式") }
    state.extensions = allowed.sorted()
    try save()
  }

  func setAutomatic(_ value: Bool) throws {
    state.automatic = value
    try save()
  }

  func disconnect() throws {
    finishAccess()
    state = State()
    try save()
  }

  func scan() throws -> [String: Any] {
    entries.removeAll()
    let root = try resolve()
    if scope == nil, !state.appDocuments, root.startAccessingSecurityScopedResource() { scope = root }
    guard files.isReadableFile(atPath: root.path) else {
      throw BookDocumentFailure(code: "scan_folder", message: "文件夹的访问授权已失效，请重新选择文件夹")
    }
    let enabled = Set(try formats())
    let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
    guard let walker = files.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else {
      throw BookDocumentFailure(code: "scan_folder", message: "无法读取所选文件夹")
    }
    let base = root.standardizedFileURL.resolvingSymlinksInPath().path
    var books: [[String: Any]] = []
    var seen = Set<String>()
    var total = 0, unchanged = 0, downloading = 0, oversized = 0, skipped = 0
    for case let url as URL in walker {
      let name = url.lastPathComponent
      if state.appDocuments && url.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path && name == "Inbox" {
        walker.skipDescendants()
        continue
      }
      // iCloud keeps undownloaded files as hidden “.name.epub.icloud” stubs.
      if name.hasPrefix(".") {
        if name.hasSuffix(".icloud"), enabled.contains((String(name.dropFirst().dropLast(7)) as NSString).pathExtension.lowercased()) {
          try? files.startDownloadingUbiquitousItem(at: url)
          downloading += 1
        }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { walker.skipDescendants() }
        continue
      }
      let ext = url.pathExtension.lowercased()
      guard enabled.contains(ext),
        let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
      let size = values.fileSize ?? 0
      guard size > 0 else { continue }
      guard size <= BookImportFormatPolicy.byteLimit(ext) else { oversized += 1; continue }
      let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
      guard resolved.hasPrefix(base + "/") else { continue }
      let relative = String(resolved.dropFirst(base.count + 1))
      let modified = Int64((values.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000)
      let signature = "\(size)-\(modified)"
      total += 1
      seen.insert(relative)
      if state.imported[relative] == signature { unchanged += 1; continue }
      guard books.count < Self.maximumBooks else { skipped += 1; continue }
      let token = UUID().uuidString
      entries[token] = Entry(url: url, relative: relative, signature: signature, name: name)
      let folder = (relative as NSString).deletingLastPathComponent
      books.append(["token": token, "name": name, "size": size, "folder": folder])
    }
    let before = state.imported.count
    state.imported = state.imported.filter { seen.contains($0.key) }
    if state.imported.count != before { try save() }
    var warnings: [String] = []
    if downloading > 0 { warnings.append("\(downloading) 本书仍在从 iCloud 下载，下次扫描时导入") }
    if oversized > 0 { warnings.append("\(oversized) 个文件超过导入大小限制，已跳过") }
    if skipped > 0 { warnings.append("新书较多，本次先列出 \(Self.maximumBooks) 本，其余下次扫描") }
    return ["books": books, "total": total, "unchanged": unchanged, "warnings": warnings]
  }

  func stage(_ token: String, documents: ManagedBookDocuments) throws -> [String: Any] {
    let entry = try lookup(token)
    var staged: URL?, failure: Error?, coordinationError: NSError?
    NSFileCoordinator().coordinate(readingItemAt: entry.url, options: [], error: &coordinationError) { readable in
      do { staged = try documents.copy(readable, maximumBytes: BookImportFormatPolicy.byteLimit(readable.pathExtension)) }
      catch { failure = error }
    }
    if let error = coordinationError ?? failure { throw error }
    guard let staged else { throw BookDocumentFailure(code: "scan_read", message: "无法读取这本书，请检查文件") }
    return ["name": entry.name, "path": staged.path]
  }

  func link(_ token: String, documents: LinkedBookDocuments) throws -> [String: Any] {
    let entry = try lookup(token)
    return try documents.retain(entry.url, relativeTo: try resolve(), name: entry.name)
  }

  func markImported(_ token: String) throws {
    let entry = try lookup(token)
    state.imported[entry.relative] = entry.signature
    try save()
  }

  func finish() throws {
    entries.removeAll()
    finishAccess()
  }

  private func lookup(_ token: String) throws -> Entry {
    guard let entry = entries[token] else {
      throw BookDocumentFailure(code: "scan_token", message: "扫描结果已过期，请重新扫描")
    }
    return entry
  }

  private func resolve() throws -> URL {
    if state.appDocuments { return documentsDirectory }
    guard let bookmark = state.bookmark else {
      throw BookDocumentFailure(code: "scan_folder", message: "请先选择要扫描的文件夹")
    }
    var stale = false
    let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
    if stale, let renewed = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil) {
      state.bookmark = renewed
      try? save()
    }
    return url
  }

  private func finishAccess() {
    scope?.stopAccessingSecurityScopedResource()
    scope = nil
  }

  private func save() throws {
    try JSONEncoder().encode(state).write(to: stateFile, options: .atomic)
  }
}
