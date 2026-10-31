import Foundation
import UIKit
import WenkuBookEngine

/// Native halves of the portable importer. Sources must be app-owned copies
/// and outputs stay inside the portable import cache.
final class NativeBookConversion {
  private let documents: ManagedBookDocuments
  private let portableRoot: URL

  init(documents: ManagedBookDocuments, portableRoot: URL) throws {
    self.documents = documents
    self.portableRoot = portableRoot.standardizedFileURL.resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: self.portableRoot, withIntermediateDirectories: true)
  }

  /// Returns the libmobi export status: 0 ok, 1 DRM, 2 invalid, 3 too large, 4 IO.
  func extractKindle(_ path: String, output: String) throws -> Int {
    let source = try documents.readableSourceURL(path)
    let folder = try owned(output)
    var isFolder: ObjCBool = false
    guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue,
      (try FileManager.default.contentsOfDirectory(atPath: folder.path)).isEmpty else {
      throw BookDocumentFailure(code: "conversion_path", message: "转换目录无效")
    }
    return Int(wenku_export_mobi(source.path, folder.path))
  }

  func extractPdf(_ path: String, output: String, name: String) throws {
    let source = try documents.readableSourceURL(path)
    try NativePdfImport.extractText(from: source, to: try owned(output), name: name)
  }

  /// RTF goes through the system text system, which also handles legacy
  /// GBK/Big5 code pages declared in the file.
  func prepareRtf(name: String, path: String) throws -> [[String: Any]] {
    let source = try documents.readableSourceURL(path)
    let text: String
    do {
      text = try NSAttributedString(url: source, options: [.documentType: NSAttributedString.DocumentType.rtf],
        documentAttributes: nil).string
    } catch {
      throw BookDocumentFailure(code: "rtf_read", message: "无法读取这个 RTF 文件")
    }
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw BookDocumentFailure(code: "rtf_empty", message: "RTF 中没有可阅读的正文")
    }
    let base = (name as NSString).deletingPathExtension
    let run = portableRoot.appendingPathComponent("rtf-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
    let target = run.appendingPathComponent("book.txt")
    try text.write(to: target, atomically: true, encoding: .utf8)
    return [["name": base + ".txt", "path": target.path]]
  }

  private func owned(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: path).standardizedFileURL
    let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
    let resolved = parent.appendingPathComponent(url.lastPathComponent)
    guard resolved.path.hasPrefix(portableRoot.path + "/") else {
      throw BookDocumentFailure(code: "conversion_path", message: "转换目录无效")
    }
    return resolved
  }
}
