import AppKit
import Foundation
import PDFKit
import Vision

enum AttachmentExtractionError: LocalizedError {
    case unsupported(String)
    case unreadable(String)
    case fileTooLarge(String, Int)

    var errorDescription: String? {
        switch self {
        case .unsupported(let type): return "Aura cannot read .\(type) files yet. Use .docx, .xlsx, PDF, an image, or plain text."
        case .unreadable(let name): return "Aura could not extract readable content from \(name)."
        case .fileTooLarge(let name, let megabytes):
            return auraText(
                "\(name) is too large. Aura accepts files up to \(megabytes) MB.",
                "\(name) 파일이 너무 큽니다. Aura는 최대 \(megabytes)MB 파일을 지원합니다."
            )
        }
    }
}

enum AttachmentExtractor {
    static let maximumFileBytes = 20 * 1_024 * 1_024
    private static let maximumCharacters = 60_000

    static func validateFileSize(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let size = values.fileSize, size > maximumFileBytes {
            throw AttachmentExtractionError.fileTooLarge(url.lastPathComponent, maximumFileBytes / 1_024 / 1_024)
        }
    }

    static func extract(from url: URL, displayName: String? = nil) throws -> ChatAttachment {
        try validateFileSize(url)
        let name = displayName ?? url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let result: (kind: String, text: String, warning: String?)

        switch ext {
        case "txt", "md", "csv", "tsv", "json", "html", "htm", "xml":
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            guard data.count <= 5_000_000, let text = String(data: data, encoding: .utf8) else {
                throw AttachmentExtractionError.unreadable(name)
            }
            result = (ext.uppercased(), text, nil)
        case "rtf":
            let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            result = ("Word/RTF", attributed.string, nil)
        case "docx":
            result = ("Word", try extractDOCX(url), nil)
        case "xlsx":
            result = ("Excel", try extractXLSX(url), nil)
        case "xls":
            throw AttachmentExtractionError.unsupported(ext)
        case "pdf":
            result = try extractPDF(url)
        case "png", "jpg", "jpeg", "heic", "tiff", "tif", "bmp", "gif", "webp":
            guard NSImage(contentsOf: url) != nil else {
                throw AttachmentExtractionError.unreadable(name)
            }
            result = ("Image", "[Visual image attached. Analyze it with the configured vision model.]", nil)
        default:
            throw AttachmentExtractionError.unsupported(ext.isEmpty ? "unknown" : ext)
        }

        let truncated = result.text.count > maximumCharacters
        let text = String(result.text.prefix(maximumCharacters))
        let warning = truncated ? "Only the first \(maximumCharacters.formatted()) characters were included." : result.warning
        let isImage = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "bmp", "gif", "webp"].contains(ext)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImage else {
            throw AttachmentExtractionError.unreadable(name)
        }
        return ChatAttachment(
            fileName: name,
            storedPath: url.path,
            kind: result.kind,
            extractedText: text.isEmpty ? "[Image attached. No readable text was detected.]" : text,
            warning: text.isEmpty ? auraText("No readable text was detected in this image.", "이 이미지에서는 읽을 수 있는 텍스트를 찾지 못했습니다.") : warning
        )
    }

    private static func extractPDF(_ url: URL) throws -> (kind: String, text: String, warning: String?) {
        guard let document = PDFDocument(url: url) else { throw AttachmentExtractionError.unreadable(url.lastPathComponent) }
        var parts: [String] = []
        var usedOCR = false
        let pageLimit = min(document.pageCount, 40)
        for index in 0..<pageLimit {
            guard let page = document.page(at: index) else { continue }
            let nativeText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if nativeText.count >= 24 {
                parts.append("[Page \(index + 1)]\n\(nativeText)")
            } else {
                let image = page.thumbnail(of: NSSize(width: 1800, height: 2400), for: .mediaBox)
                if let cgImage = image.cgImageForOCR {
                    let recognized = try recognizeText(in: cgImage)
                    if !recognized.isEmpty {
                        usedOCR = true
                        parts.append("[Page \(index + 1), OCR]\n\(recognized)")
                    }
                }
            }
        }
        let warning = document.pageCount > pageLimit
            ? "Only the first \(pageLimit) PDF pages were processed."
            : nil
        return (usedOCR ? "PDF + OCR" : "PDF", parts.joined(separator: "\n\n"), warning)
    }

    private static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = AuraEdition.current == .korean ? ["ko-KR", "en-US"] : ["en-US", "ko-KR"]
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    private static func extractDOCX(_ url: URL) throws -> String {
        let data = try unzipEntry("word/document.xml", from: url)
        let delegate = WordXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? AttachmentExtractionError.unreadable(url.lastPathComponent) }
        return delegate.text
    }

    private static func extractXLSX(_ url: URL) throws -> String {
        let sharedStrings: [String]
        if let data = try? unzipEntry("xl/sharedStrings.xml", from: url) {
            let delegate = SharedStringsXMLDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            _ = parser.parse()
            sharedStrings = delegate.values
        } else {
            sharedStrings = []
        }

        let sheetData = try unzipEntry("xl/worksheets/sheet1.xml", from: url)
        let delegate = WorksheetXMLDelegate(sharedStrings: sharedStrings)
        let parser = XMLParser(data: sheetData)
        parser.delegate = delegate
        guard parser.parse() else { throw parser.parserError ?? AttachmentExtractionError.unreadable(url.lastPathComponent) }
        return delegate.rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    private static func unzipEntry(_ entry: String, from archive: URL) throws -> Data {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, entry]
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else {
            throw AttachmentExtractionError.unreadable(archive.lastPathComponent)
        }
        return data
    }
}

private extension NSImage {
    var cgImageForOCR: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

private final class WordXMLDelegate: NSObject, XMLParserDelegate {
    private var collectingText = false
    private var buffer = ""
    private(set) var text = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName.hasSuffix(":t") || elementName == "t" { collectingText = true; buffer = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingText { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.hasSuffix(":t") || elementName == "t" {
            text += buffer
            collectingText = false
        } else if elementName.hasSuffix(":p") || elementName == "p" {
            text += "\n"
        } else if elementName.hasSuffix(":tab") || elementName == "tab" {
            text += "\t"
        }
    }
}

private final class SharedStringsXMLDelegate: NSObject, XMLParserDelegate {
    private var collectingText = false
    private var current = ""
    private(set) var values: [String] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "si" { current = "" }
        if elementName == "t" { collectingText = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" { collectingText = false }
        if elementName == "si" { values.append(current) }
    }
}

private final class WorksheetXMLDelegate: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var row: [String] = []
    private var value = ""
    private var cellType = ""
    private var collectingValue = false
    private(set) var rows: [[String]] = []

    init(sharedStrings: [String]) { self.sharedStrings = sharedStrings }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "row" { row = [] }
        if elementName == "c" { cellType = attributeDict["t"] ?? ""; value = "" }
        if elementName == "v" || elementName == "t" { collectingValue = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if collectingValue { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" || elementName == "t" { collectingValue = false }
        if elementName == "c" {
            if cellType == "s", let index = Int(value), sharedStrings.indices.contains(index) {
                row.append(sharedStrings[index])
            } else {
                row.append(value)
            }
        }
        if elementName == "row" { rows.append(row) }
    }
}
