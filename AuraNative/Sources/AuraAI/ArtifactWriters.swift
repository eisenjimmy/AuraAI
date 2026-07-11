import Foundation

enum ArtifactWriter {
    static func markdown(content: String, to url: URL) throws {
        try prepare(url)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    static func html(title: String, summary: String, bodyHTML: String, to url: URL) throws {
        let safeBody = sanitizeHTML(bodyHTML)
        let document = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(escapeHTML(title))</title>
          <style>
            :root { color-scheme: light; --paper:#f7f3ea; --ink:#22211e; --muted:#67635b; --line:#d7d0c3; --accent:#156f72; --panel:#fffdf8; }
            * { box-sizing:border-box; }
            body { margin:0; background:var(--paper); color:var(--ink); font:16px/1.65 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; }
            main { width:min(920px,calc(100% - 40px)); margin:48px auto 80px; }
            header { border-bottom:2px solid var(--ink); padding-bottom:24px; margin-bottom:32px; }
            h1 { margin:0 0 10px; font:700 clamp(2rem,5vw,3.6rem)/1.05 Georgia,serif; }
            h2 { margin:36px 0 10px; font:700 1.55rem/1.2 Georgia,serif; }
            h3 { margin:24px 0 8px; font-size:1.05rem; }
            p,ul,ol,table,pre,blockquote { margin:0 0 18px; }
            .summary { color:var(--muted); font-size:1.12rem; max-width:70ch; }
            section { padding:24px 0; border-bottom:1px solid var(--line); }
            table { width:100%; border-collapse:collapse; background:var(--panel); }
            th,td { padding:10px 12px; text-align:left; border:1px solid var(--line); vertical-align:top; }
            th { background:#e7f0ed; }
            code,pre { font-family:"SFMono-Regular",Consolas,monospace; }
            pre { padding:16px; overflow:auto; background:#242521; color:#f7f3ea; }
            blockquote { margin-left:0; padding:12px 18px; border-left:4px solid var(--accent); background:var(--panel); }
            a { color:var(--accent); }
            @media (max-width:600px) { main { width:min(100% - 24px,920px); margin-top:28px; } th,td { padding:8px; } }
          </style>
        </head>
        <body>
          <main>
            <header><h1>\(escapeHTML(title))</h1><p class="summary">\(escapeHTML(summary))</p></header>
            \(safeBody)
          </main>
        </body>
        </html>
        """
        try prepare(url)
        try document.write(to: url, atomically: true, encoding: .utf8)
    }

    static func spreadsheet(title: String, sheetName: String, headers: [String], rows: [[JSONValue]], to url: URL) throws {
        guard !headers.isEmpty else { throw LLMClientError.badResponse("Spreadsheet requires at least one header.") }
        guard headers.count <= 200, rows.count <= 20_000 else {
            throw LLMClientError.badResponse("Spreadsheet exceeds Aura's 200-column or 20,000-row limit.")
        }

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("aura-xlsx-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)

        try writeXML(contentTypes, to: temporary.appendingPathComponent("[Content_Types].xml"))
        try writeXML(rootRelationships, to: temporary.appendingPathComponent("_rels/.rels"))
        try writeXML(coreProperties, to: temporary.appendingPathComponent("docProps/core.xml"))
        try writeXML(appProperties, to: temporary.appendingPathComponent("docProps/app.xml"))
        try writeXML(workbookXML(sheetName), to: temporary.appendingPathComponent("xl/workbook.xml"))
        try writeXML(workbookRelationships, to: temporary.appendingPathComponent("xl/_rels/workbook.xml.rels"))
        try writeXML(stylesXML, to: temporary.appendingPathComponent("xl/styles.xml"))
        try writeXML(sheetXML(title: title, headers: headers, rows: rows), to: temporary.appendingPathComponent("xl/worksheets/sheet1.xml"))

        try prepare(url)
        try? FileManager.default.removeItem(at: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", url.path, "."]
        process.currentDirectoryURL = temporary
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
            throw LLMClientError.badResponse("Could not package the Excel workbook.")
        }
    }

    static func sanitizeHTML(_ input: String) -> String {
        var output = input
        let blockedElements = ["script", "iframe", "object", "embed", "form", "input", "button"]
        for element in blockedElements {
            output = output.replacingOccurrences(
                of: "(?is)<\(element)\\b[^>]*>.*?</\(element)\\s*>",
                with: "",
                options: .regularExpression
            )
            output = output.replacingOccurrences(
                of: "(?is)<\(element)\\b[^>]*/?>",
                with: "",
                options: .regularExpression
            )
        }
        output = output.replacingOccurrences(of: "(?is)\\son[a-z]+\\s*=\\s*(['\"]).*?\\1", with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?i)javascript\\s*:", with: "", options: .regularExpression)
        return output
    }

    private static func prepare(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    private static func writeXML(_ content: String, to url: URL) throws {
        try prepare(url)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func sheetXML(title: String, headers: [String], rows: [[JSONValue]]) -> String {
        let widthXML = headers.enumerated().map { index, header in
            let dataWidth = rows.prefix(200).map { row in index < row.count ? row[index].displayText.count : 0 }.max() ?? 0
            let width = min(44, max(10, max(header.count, dataWidth) + 2))
            return "<col min=\"\(index + 1)\" max=\"\(index + 1)\" width=\"\(width)\" customWidth=\"1\"/>"
        }.joined()
        var rowXML = "<row r=\"1\" ht=\"30\" customHeight=\"1\"><c r=\"A1\" s=\"1\" t=\"inlineStr\"><is><t>\(escapeXML(title))</t></is></c></row>"
        rowXML += "<row r=\"2\">" + headers.enumerated().map { index, value in
            cellXML(value: .string(value), reference: "\(columnName(index + 1))2", style: 2)
        }.joined() + "</row>"
        for (rowIndex, row) in rows.enumerated() {
            let excelRow = rowIndex + 3
            rowXML += "<row r=\"\(excelRow)\">"
            for column in headers.indices {
                let value = column < row.count ? row[column] : .null
                rowXML += cellXML(value: value, reference: "\(columnName(column + 1))\(excelRow)", style: 3)
            }
            rowXML += "</row>"
        }
        let lastColumn = columnName(headers.count)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetViews><sheetView showGridLines="0" workbookViewId="0"><pane ySplit="2" topLeftCell="A3" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
          <cols>\(widthXML)</cols>
          <sheetData>\(rowXML)</sheetData>
          <mergeCells count="1"><mergeCell ref="A1:\(lastColumn)1"/></mergeCells>
          <autoFilter ref="A2:\(lastColumn)\(max(2, rows.count + 2))"/>
        </worksheet>
        """
    }

    private static func cellXML(value: JSONValue, reference: String, style: Int) -> String {
        switch value {
        case .number(let number):
            return "<c r=\"\(reference)\" s=\"4\"><v>\(number)</v></c>"
        case .boolean(let boolean):
            return "<c r=\"\(reference)\" s=\"\(style)\" t=\"b\"><v>\(boolean ? 1 : 0)</v></c>"
        case .null:
            return "<c r=\"\(reference)\" s=\"\(style)\"/>"
        default:
            return "<c r=\"\(reference)\" s=\"\(style)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escapeXML(value.displayText))</t></is></c>"
        }
    }

    private static func columnName(_ index: Int) -> String {
        var value = index
        var result = ""
        while value > 0 {
            value -= 1
            result = String(UnicodeScalar(65 + value % 26)!) + result
            value /= 26
        }
        return result
    }

    private static func workbookXML(_ sheetName: String) -> String {
        let clean = String(sheetName.filter { !"[]:*?/\\".contains($0) }.prefix(31))
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"\(escapeXML(clean.isEmpty ? "Sheet1" : clean))\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"
    }

    private static func escapeXML(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func escapeHTML(_ value: String) -> String { escapeXML(value) }

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/><Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/></Types>
    """
    private static let rootRelationships = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/></Relationships>"
    private static let workbookRelationships = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>"
    private static let coreProperties = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:creator>Aura AI</dc:creator><dc:title>Aura workbook</dc:title></cp:coreProperties>"
    private static let appProperties = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\"><Application>Aura AI</Application></Properties>"
    private static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
      <fonts count="3"><font><sz val="11"/><name val="Aptos"/></font><font><b/><sz val="18"/><color rgb="FFFFFFFF"/><name val="Aptos Display"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Aptos"/></font></fonts>
      <fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF155F63"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FF297B7E"/><bgColor indexed="64"/></patternFill></fill></fills>
      <borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border><border><left/><right/><top/><bottom style="thin"><color rgb="FFD9D9D9"/></bottom><diagonal/></border></borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="5"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center"/></xf><xf numFmtId="0" fontId="2" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center"/></xf><xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="4" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/></cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>
    """
}

extension JSONValue {
    var displayText: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? String(Int(value)) : String(value)
        case .boolean(let value): return value ? "TRUE" : "FALSE"
        case .object(let value): return value.map { "\($0.key): \($0.value.displayText)" }.sorted().joined(separator: ", ")
        case .array(let value): return value.map(\.displayText).joined(separator: ", ")
        case .null: return ""
        }
    }
}
