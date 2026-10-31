import Foundation
import PDFKit

/// Text-layer extraction only. Scanned PDFs have no text layer and fail with a
/// clear message instead of an empty book.
enum NativePdfImport {
  private static let maximumPages = 10000

  static func extractText(from source: URL, to output: URL, name: String) throws {
    guard let document = PDFDocument(url: source) else {
      throw BookDocumentFailure(code: "pdf_read", message: "无法打开这个 PDF 文件")
    }
    if document.isLocked {
      throw BookDocumentFailure(code: "pdf_locked", message: "PDF 已加密，请先移除密码后导入")
    }
    guard document.pageCount <= maximumPages else {
      throw BookDocumentFailure(code: "pdf_pages", message: "PDF 页数过多，无法导入")
    }
    guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
      throw BookDocumentFailure(code: "pdf_write", message: "转换时无法写入文件，请检查存储空间")
    }
    let sink = try FileHandle(forWritingTo: output)
    defer { try? sink.close() }
    var written = 0
    for index in 0..<document.pageCount {
      try autoreleasepool {
        guard let text = document.page(at: index)?.string?
          .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        let block = Data(((written > 0 ? "\n\n" : "") + text).utf8)
        written += block.count
        guard written <= 256 * 1024 * 1024 else {
          throw BookDocumentFailure(code: "pdf_size", message: "PDF 文字过多，无法导入")
        }
        sink.write(block)
      }
    }
    guard written > 0 else {
      throw BookDocumentFailure(code: "pdf_empty", message: "PDF 中没有可提取的文字，扫描版 PDF 暂不支持")
    }
  }
}
