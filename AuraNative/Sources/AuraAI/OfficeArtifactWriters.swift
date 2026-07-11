import Foundation

struct PresentationSlide: Equatable {
    var title: String
    var body: String
    var bullets: [String]
}

extension ArtifactWriter {
    static func word(title: String, content: String, to url: URL) throws {
        try OfficeArtifactWriter.word(title: title, content: content, to: url)
    }

    static func presentation(title: String, subtitle: String, slides: [PresentationSlide], to url: URL) throws {
        try OfficeArtifactWriter.presentation(title: title, subtitle: subtitle, slides: slides, to: url)
    }
}

private enum OfficeArtifactWriter {
    static func word(title: String, content: String, to url: URL) throws {
        let files = [
            "[Content_Types].xml": wordContentTypes,
            "_rels/.rels": rootRelationships(target: "word/document.xml"),
            "docProps/core.xml": coreProperties(title),
            "docProps/app.xml": appProperties("Aura AI"),
            "word/document.xml": wordDocument(title: title, content: content),
            "word/styles.xml": wordStyles,
            "word/numbering.xml": wordNumbering,
            "word/_rels/document.xml.rels": wordRelationships
        ]
        try package(files, to: url)
    }

    static func presentation(title: String, subtitle: String, slides: [PresentationSlide], to url: URL) throws {
        guard !slides.isEmpty else { throw LLMClientError.badResponse("Presentation requires at least one content slide.") }
        let allSlides = [PresentationSlide(title: title, body: subtitle, bullets: [])] + slides
        var files = [
            "[Content_Types].xml": presentationContentTypes(slideCount: allSlides.count),
            "_rels/.rels": rootRelationships(target: "ppt/presentation.xml"),
            "docProps/core.xml": coreProperties(title),
            "docProps/app.xml": appProperties("Aura AI"),
            "ppt/presentation.xml": presentationXML(slideCount: allSlides.count),
            "ppt/_rels/presentation.xml.rels": presentationRelationships(slideCount: allSlides.count),
            "ppt/slideMasters/slideMaster1.xml": slideMasterXML,
            "ppt/slideMasters/_rels/slideMaster1.xml.rels": slideMasterRelationships,
            "ppt/slideLayouts/slideLayout1.xml": slideLayoutXML,
            "ppt/slideLayouts/_rels/slideLayout1.xml.rels": slideLayoutRelationships,
            "ppt/theme/theme1.xml": themeXML
        ]
        for (index, slide) in allSlides.enumerated() {
            let number = index + 1
            files["ppt/slides/slide\(number).xml"] = slideXML(slide, isTitleSlide: index == 0)
            files["ppt/slides/_rels/slide\(number).xml.rels"] = slideRelationships
        }
        try package(files, to: url)
    }

    private static func package(_ files: [String: String], to url: URL) throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("aura-office-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        for (path, content) in files {
            let destination = temporary.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: destination, atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-q", "-r", url.path, "."]
        process.currentDirectoryURL = temporary
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: url.path) else {
            throw LLMClientError.badResponse("Could not package the Office document.")
        }
    }

    private static func wordDocument(title: String, content: String) -> String {
        let blocks = content.split(whereSeparator: \.isNewline).map(String.init)
        let contentXML = blocks.compactMap { line -> String? in
            let clean = line.trimmingCharacters(in: .whitespaces)
            guard !clean.isEmpty else { return nil }
            if clean.hasPrefix("### ") { return wordParagraph(String(clean.dropFirst(4)), style: "Heading3") }
            if clean.hasPrefix("## ") { return wordParagraph(String(clean.dropFirst(3)), style: "Heading2") }
            if clean.hasPrefix("# ") { return wordParagraph(String(clean.dropFirst(2)), style: "Heading1") }
            if clean.hasPrefix("- ") || clean.hasPrefix("* ") { return wordBullet(String(clean.dropFirst(2))) }
            return wordParagraph(clean, style: "Normal")
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(wordParagraph(title, style: "Title"))
            \(contentXML)
            <w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/><w:docGrid w:linePitch="360"/></w:sectPr>
          </w:body>
        </w:document>
        """
    }

    private static func wordParagraph(_ text: String, style: String) -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"\(style)\"/></w:pPr><w:r><w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r></w:p>"
    }

    private static func wordBullet(_ text: String) -> String {
        "<w:p><w:pPr><w:pStyle w:val=\"Normal\"/><w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr></w:pPr><w:r><w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r></w:p>"
    }

    private static func presentationXML(slideCount: Int) -> String {
        let slideIDs = (0..<slideCount).map { offset in
            "<p:sldId id=\"\(256 + offset)\" r:id=\"rId\(offset + 2)\"/>"
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
          <p:sldIdLst>\(slideIDs)</p:sldIdLst>
          <p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>
          <p:notesSz cx="6858000" cy="9144000"/>
        </p:presentation>
        """
    }

    private static func presentationRelationships(slideCount: Int) -> String {
        let slides = (0..<slideCount).map { offset in
            "<Relationship Id=\"rId\(offset + 2)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide\" Target=\"slides/slide\(offset + 1).xml\"/>"
        }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"slideMasters/slideMaster1.xml\"/>\(slides)</Relationships>"
    }

    private static func slideXML(_ slide: PresentationSlide, isTitleSlide: Bool) -> String {
        let titleShape = textShape(id: 2, name: "Title", x: 914400, y: isTitleSlide ? 1500000 : 600000, width: 10363200, height: isTitleSlide ? 1250000 : 650000, text: slide.title, size: isTitleSlide ? 4800 : 3200, color: "163A4A", bold: true, bullet: false)
        let bodyText = isTitleSlide ? slide.body : [slide.body, slide.bullets.joined(separator: "\n")].filter { !$0.isEmpty }.joined(separator: "\n")
        let bodyShape = textShape(id: 3, name: "Body", x: 1280000, y: isTitleSlide ? 3000000 : 1550000, width: 9500000, height: isTitleSlide ? 900000 : 4000000, text: bodyText, size: isTitleSlide ? 2300 : 1900, color: "425466", bold: false, bullet: !isTitleSlide && !slide.bullets.isEmpty)
        let accent = isTitleSlide ? solidShape(id: 4, name: "Accent", x: 914400, y: 2800000, width: 1850000, height: 90000, color: "237B7D") : solidShape(id: 4, name: "Accent", x: 0, y: 0, width: 12192000, height: 150000, color: "237B7D")
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">
          <p:cSld><p:spTree>\(groupShape)\(accent)\(titleShape)\(bodyShape)</p:spTree></p:cSld>
          <p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>
        </p:sld>
        """
    }

    private static func textShape(id: Int, name: String, x: Int, y: Int, width: Int, height: Int, text: String, size: Int, color: String, bold: Bool, bullet: Bool) -> String {
        let paragraphs = text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { index, line -> String in
            let isBullet = bullet && index > 0
            let prefix = isBullet ? "<a:pPr marL=\"457200\" indent=\"-228600\"><a:buChar char=\"•\"/></a:pPr>" : "<a:pPr/>"
            return "<a:p>\(prefix)<a:r><a:rPr lang=\"en-US\" sz=\"\(size)\"\(bold ? " b=\"1\"" : "")><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill><a:latin typeface=\"Aptos\"/></a:rPr><a:t>\(escape(String(line)))</a:t></a:r><a:endParaRPr lang=\"en-US\" sz=\"\(size)\"/></a:p>"
        }.joined()
        return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap=\"square\"/><a:lstStyle/>\(paragraphs)</p:txBody></p:sp>"
    }

    private static func solidShape(id: Int, name: String, x: Int, y: Int, width: Int, height: Int, color: String) -> String {
        "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"\(name)\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:solidFill><a:srgbClr val=\"\(color)\"/></a:solidFill><a:ln><a:noFill/></a:ln></p:spPr></p:sp>"
    }

    private static let groupShape = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
    private static let slideRelationships = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/></Relationships>"
    private static let slideMasterRelationships = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout\" Target=\"../slideLayouts/slideLayout1.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme\" Target=\"../theme/theme1.xml\"/></Relationships>"
    private static let slideLayoutRelationships = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster\" Target=\"../slideMasters/slideMaster1.xml\"/></Relationships>"
    private static let slideMasterXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:sldMaster xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:cSld name=\"Aura Master\"><p:spTree>\(groupShape)</p:spTree></p:cSld><p:clrMap bg1=\"lt1\" tx1=\"dk1\" bg2=\"lt2\" tx2=\"dk2\" accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" hlink=\"hlink\" folHlink=\"folHlink\"/><p:sldLayoutIdLst><p:sldLayoutId id=\"1\" r:id=\"rId1\"/></p:sldLayoutIdLst><p:txStyles/></p:sldMaster>"
    private static let slideLayoutXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><p:sldLayout xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" type=\"blank\" preserve=\"1\"><p:cSld name=\"Blank\"><p:spTree>\(groupShape)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>"
    private static let themeXML = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"Aura\"><a:themeElements><a:clrScheme name=\"Aura\"><a:dk1><a:srgbClr val=\"1F2933\"/></a:dk1><a:lt1><a:srgbClr val=\"FFFFFF\"/></a:lt1><a:dk2><a:srgbClr val=\"163A4A\"/></a:dk2><a:lt2><a:srgbClr val=\"F6F8FA\"/></a:lt2><a:accent1><a:srgbClr val=\"237B7D\"/></a:accent1><a:accent2><a:srgbClr val=\"4472C4\"/></a:accent2><a:accent3><a:srgbClr val=\"70AD47\"/></a:accent3><a:accent4><a:srgbClr val=\"ED7D31\"/></a:accent4><a:accent5><a:srgbClr val=\"A5A5A5\"/></a:accent5><a:accent6><a:srgbClr val=\"FFC000\"/></a:accent6><a:hlink><a:srgbClr val=\"0563C1\"/></a:hlink><a:folHlink><a:srgbClr val=\"954F72\"/></a:folHlink></a:clrScheme><a:fontScheme name=\"Aura\"><a:majorFont><a:latin typeface=\"Aptos Display\"/><a:ea typeface=\"Malgun Gothic\"/><a:cs typeface=\"Aptos Display\"/></a:majorFont><a:minorFont><a:latin typeface=\"Aptos\"/><a:ea typeface=\"Malgun Gothic\"/><a:cs typeface=\"Aptos\"/></a:minorFont></a:fontScheme><a:fmtScheme name=\"Aura\"><a:fillStyleLst/><a:lnStyleLst/><a:effectStyleLst/><a:bgFillStyleLst/></a:fmtScheme></a:themeElements></a:theme>"
    private static let wordContentTypes = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/><Override PartName=\"/word/numbering.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/><Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/></Types>"
    private static func presentationContentTypes(slideCount: Int) -> String {
        let slides = (1...slideCount).map { "<Override PartName=\"/ppt/slides/slide\($0).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slide+xml\"/>" }.joined()
        return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/ppt/presentation.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml\"/><Override PartName=\"/ppt/slideMasters/slideMaster1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml\"/><Override PartName=\"/ppt/slideLayouts/slideLayout1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml\"/><Override PartName=\"/ppt/theme/theme1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.theme+xml\"/><Override PartName=\"/docProps/core.xml\" ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/><Override PartName=\"/docProps/app.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.extended-properties+xml\"/>\(slides)</Types>"
    }
    private static let wordRelationships = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/></Relationships>"
    private static let wordStyles = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Aptos\" w:hAnsi=\"Aptos\" w:eastAsia=\"Malgun Gothic\"/><w:sz w:val=\"22\"/><w:lang w:val=\"en-US\" w:eastAsia=\"ko-KR\"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:qFormat/><w:pPr><w:spacing w:after=\"160\" w:line=\"276\" w:lineRule=\"auto\"/></w:pPr></w:style><w:style w:type=\"paragraph\" w:styleId=\"Title\"><w:name w:val=\"Title\"/><w:basedOn w:val=\"Normal\"/><w:qFormat/><w:pPr><w:spacing w:after=\"360\"/></w:pPr><w:rPr><w:rFonts w:ascii=\"Aptos Display\" w:hAnsi=\"Aptos Display\" w:eastAsia=\"Malgun Gothic\"/><w:color w:val=\"163A4A\"/><w:sz w:val=\"40\"/><w:b/></w:rPr></w:style><w:style w:type=\"paragraph\" w:styleId=\"Heading1\"><w:name w:val=\"heading 1\"/><w:basedOn w:val=\"Normal\"/><w:qFormat/><w:pPr><w:spacing w:before=\"300\" w:after=\"120\"/></w:pPr><w:rPr><w:color w:val=\"237B7D\"/><w:sz w:val=\"30\"/><w:b/></w:rPr></w:style><w:style w:type=\"paragraph\" w:styleId=\"Heading2\"><w:name w:val=\"heading 2\"/><w:basedOn w:val=\"Normal\"/><w:qFormat/><w:pPr><w:spacing w:before=\"220\" w:after=\"80\"/></w:pPr><w:rPr><w:color w:val=\"163A4A\"/><w:sz w:val=\"26\"/><w:b/></w:rPr></w:style><w:style w:type=\"paragraph\" w:styleId=\"Heading3\"><w:name w:val=\"heading 3\"/><w:basedOn w:val=\"Normal\"/><w:qFormat/><w:pPr><w:spacing w:before=\"180\" w:after=\"60\"/></w:pPr><w:rPr><w:color w:val=\"425466\"/><w:sz w:val=\"24\"/><w:b/></w:rPr></w:style></w:styles>"
    private static let wordNumbering = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><w:numbering xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/><w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"•\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:tabs><w:tab w:val=\"num\" w:pos=\"720\"/></w:tabs><w:ind w:left=\"720\" w:hanging=\"360\"/></w:pPr><w:rPr><w:rFonts w:ascii=\"Symbol\" w:hAnsi=\"Symbol\"/></w:rPr></w:lvl></w:abstractNum><w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num></w:numbering>"
    private static func rootRelationships(target: String) -> String { "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"\(target)\"/><Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" Target=\"docProps/core.xml\"/><Relationship Id=\"rId3\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties\" Target=\"docProps/app.xml\"/></Relationships>" }
    private static func coreProperties(_ title: String) -> String { "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><dc:creator>Aura AI</dc:creator><dc:title>\(escape(title))</dc:title></cp:coreProperties>" }
    private static func appProperties(_ application: String) -> String { "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Properties xmlns=\"http://schemas.openxmlformats.org/officeDocument/2006/extended-properties\" xmlns:vt=\"http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes\"><Application>\(escape(application))</Application></Properties>" }
    private static func escape(_ value: String) -> String { value.unicodeScalars.filter { $0.value >= 0x20 || $0 == "\t" || $0 == "\n" }.reduce("") { $0 + String($1) }.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "'", with: "&apos;") }
}
