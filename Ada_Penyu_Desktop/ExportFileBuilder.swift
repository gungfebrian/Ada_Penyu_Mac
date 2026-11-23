import CoreGraphics
import CoreText
import Foundation

/// Builds client-side export payloads (CSV, XLSX, PDF) for demo workspaces and
/// local verification, honoring scope, date range, selected fields, and format.
enum ExportFileBuilder {
    struct Row {
        let turtle: Turtle
        let detail: TurtleDetailData
    }

    static func build(
        request: ExportRequest,
        rows: [Row]
    ) -> DownloadedFile {
        let columns = columnDefinitions(for: request.fields)
        let tableRows: [[String]] = rows.map { row in
            columns.map { $0.value(row) }
        }
        let baseName = filenameBase(for: request)

        switch request.format {
        case .csv:
            let data = buildCSV(headers: columns.map(\.header), rows: tableRows)
            return DownloadedFile(
                data: data,
                filename: "\(baseName).csv",
                contentType: "text/csv"
            )

        case .xlsx:
            let data = buildXLSX(
                sheetName: "Individuals",
                headers: columns.map(\.header),
                rows: tableRows
            )
            return DownloadedFile(
                data: data,
                filename: "\(baseName).xlsx",
                contentType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            )

        case .pdf:
            let data = buildPDF(
                request: request,
                headers: columns.map(\.header),
                rows: tableRows
            )
            return DownloadedFile(
                data: data,
                filename: "\(baseName).pdf",
                contentType: "application/pdf"
            )
        }
    }

    /// Parses a `Content-Disposition` HTTP header cleanly, handling quoted values,
    /// extra semicolon-delimited parameters, and RFC 5987 `filename*=UTF-8''...`.
    static func parseContentDispositionFilename(_ header: String?, fallback: String) -> String {
        guard let header, !header.isEmpty else { return fallback }
        let parts = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if let extended = parts.first(where: { $0.lowercased().hasPrefix("filename*=") }) {
            let value = String(extended.dropFirst("filename*=".count))
            let cleaned: String
            if let range = value.range(of: "''") {
                cleaned = String(value[range.upperBound...]).removingPercentEncoding ?? String(value[range.upperBound...])
            } else {
                cleaned = value
            }
            let sanitized = Self.sanitizeFilename(cleaned)
            if !sanitized.isEmpty { return sanitized }
        }

        if let plain = parts.first(where: { $0.lowercased().hasPrefix("filename=") }) {
            let sanitized = Self.sanitizeFilename(String(plain.dropFirst("filename=".count)))
            if !sanitized.isEmpty { return sanitized }
        }

        return fallback
    }

    private static func sanitizeFilename(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        let normalized = trimmed.replacingOccurrences(of: "\\", with: "/")
        let lastComponent = (normalized as NSString).lastPathComponent
        let clean = lastComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean != "." && clean != ".." else { return "" }
        return clean
    }

    // MARK: - Column Definitions

    private struct ColumnDef {
        let header: String
        let value: (Row) -> String
    }

    private static func columnDefinitions(for fields: Set<ExportField>) -> [ColumnDef] {
        let effective = fields.isEmpty ? Set([ExportField.profile]) : fields
        var columns: [ColumnDef] = [
            ColumnDef(header: "ID", value: { $0.turtle.id }),
            ColumnDef(header: "Name", value: { $0.turtle.displayName }),
        ]

        if effective.contains(.profile) {
            columns.append(contentsOf: [
                ColumnDef(header: "Profile Code", value: { $0.turtle.profileCode ?? $0.turtle.id }),
                ColumnDef(header: "Species", value: { $0.turtle.species.rawValue }),
                ColumnDef(header: "Location", value: { $0.turtle.location }),
                ColumnDef(header: "First Recorded", value: { $0.turtle.firstRecorded }),
                ColumnDef(header: "Last Seen", value: { $0.turtle.lastSeen }),
                ColumnDef(header: "Total Sightings", value: { String($0.turtle.sightings) }),
                ColumnDef(header: "Condition", value: { $0.turtle.condition.rawValue }),
            ])
        }

        if effective.contains(.measurements) {
            columns.append(contentsOf: [
                ColumnDef(header: "CCL (cm)", value: { row in
                    row.detail.measurements.first?.length.map { String(format: "%.1f", $0) } ?? ""
                }),
                ColumnDef(header: "CCW (cm)", value: { row in
                    row.detail.measurements.first?.width.map { String(format: "%.1f", $0) } ?? ""
                }),
                ColumnDef(header: "Weight (kg)", value: { row in
                    row.detail.measurements.first?.weight.map { String(format: "%.1f", $0) } ?? ""
                }),
            ])
        }

        if effective.contains(.sightingLog) {
            columns.append(ColumnDef(header: "Sighting Log", value: { row in
                row.detail.sightingLogs
                    .map { "\($0.date) @ \($0.location) (\($0.status))" }
                    .joined(separator: " | ")
            }))
        }

        if effective.contains(.conditionHistory) {
            columns.append(ColumnDef(header: "Condition History", value: { row in
                let records = row.detail.logs.filter(\.isBodyConditionRecord)
                if records.isEmpty { return row.turtle.condition.rawValue }
                return records.map { rec in
                    let part = rec.bodyPart?.displayName ?? "General"
                    return "\(rec.date): \(part) - \(rec.status)"
                }.joined(separator: " | ")
            }))
        }

        if effective.contains(.coordinates) {
            columns.append(contentsOf: [
                ColumnDef(header: "Latitude", value: { row in
                    row.turtle.coordinate.map { String(format: "%.5f", $0.latitude) } ?? ""
                }),
                ColumnDef(header: "Longitude", value: { row in
                    row.turtle.coordinate.map { String(format: "%.5f", $0.longitude) } ?? ""
                }),
            ])
        }

        if effective.contains(.photo) {
            columns.append(contentsOf: [
                ColumnDef(header: "Left Photo", value: { $0.turtle.leftPhotoURL ?? "" }),
                ColumnDef(header: "Right Photo", value: { $0.turtle.rightPhotoURL ?? "" }),
            ])
        }

        return columns
    }

    private static func filenameBase(for request: ExportRequest) -> String {
        let scopeToken = request.scope == .all ? "all" : "filtered"
        return "ada-penyu-individuals-\(scopeToken)-\(request.range.rawValue)"
    }

    // MARK: - CSV (RFC 4180)

    static func buildCSV(headers: [String], rows: [[String]]) -> Data {
        func escape(_ cell: String) -> String {
            let needsQuotes = cell.contains(",") || cell.contains("\"") || cell.contains("\n") || cell.contains("\r")
            guard needsQuotes else { return cell }
            return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }

        var lines: [String] = []
        lines.reserveCapacity(rows.count + 1)
        lines.append(headers.map(escape).joined(separator: ","))
        for row in rows {
            lines.append(row.map(escape).joined(separator: ","))
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    // MARK: - XLSX (Minimal Valid OOXML Package in Uncompressed ZIP)

    static func buildXLSX(sheetName: String, headers: [String], rows: [[String]]) -> Data {
        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
          <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        </Types>
        """

        let rootRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """

        let workbook = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
          <sheets>
            <sheet name="\(xmlEscape(sheetName))" sheetId="1" r:id="rId1"/>
          </sheets>
        </workbook>
        """

        let workbookRels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        </Relationships>
        """

        var sheetRows = ""
        let allRows = [headers] + rows
        for (rowIdx, cells) in allRows.enumerated() {
            let r = rowIdx + 1
            sheetRows += "<row r=\"\(r)\">"
            for (colIdx, raw) in cells.enumerated() {
                let ref = "\(excelColumnName(colIdx))\(r)"
                sheetRows += "<c r=\"\(ref)\" t=\"inlineStr\"><is><t>\(xmlEscape(raw))</t></is></c>"
            }
            sheetRows += "</row>"
        }

        let worksheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
          <sheetData>\(sheetRows)</sheetData>
        </worksheet>
        """

        return makeStoreZip(entries: [
            ("[Content_Types].xml", Data(contentTypes.utf8)),
            ("_rels/.rels", Data(rootRels.utf8)),
            ("xl/workbook.xml", Data(workbook.utf8)),
            ("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8)),
            ("xl/worksheets/sheet1.xml", Data(worksheet.utf8)),
        ])
    }

    private static func xmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func excelColumnName(_ index: Int) -> String {
        var n = index
        var result = ""
        repeat {
            let scalar = UnicodeScalar(65 + (n % 26))!
            result = String(scalar) + result
            n = (n / 26) - 1
        } while n >= 0
        return result
    }

    private static func makeStoreZip(entries: [(String, Data)]) -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var entryOffsets: [(nameData: Data, data: Data, crc: UInt32, offset: UInt32)] = []

        func appendUInt16(_ value: UInt16, to buffer: inout Data) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { buffer.append(contentsOf: $0) }
        }
        func appendUInt32(_ value: UInt32, to buffer: inout Data) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { buffer.append(contentsOf: $0) }
        }

        for (name, data) in entries {
            let nameData = Data(name.utf8)
            let crc = crc32(data)
            let offset = UInt32(archive.count)
            entryOffsets.append((nameData, data, crc, offset))

            appendUInt32(0x04034b50, to: &archive)
            appendUInt16(20, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt16(0, to: &archive)
            appendUInt32(crc, to: &archive)
            appendUInt32(UInt32(data.count), to: &archive)
            appendUInt32(UInt32(data.count), to: &archive)
            appendUInt16(UInt16(nameData.count), to: &archive)
            appendUInt16(0, to: &archive)
            archive.append(nameData)
            archive.append(data)
        }

        let centralOffset = UInt32(archive.count)
        for item in entryOffsets {
            appendUInt32(0x02014b50, to: &centralDirectory)
            appendUInt16(20, to: &centralDirectory)
            appendUInt16(20, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt32(item.crc, to: &centralDirectory)
            appendUInt32(UInt32(item.data.count), to: &centralDirectory)
            appendUInt32(UInt32(item.data.count), to: &centralDirectory)
            appendUInt16(UInt16(item.nameData.count), to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt16(0, to: &centralDirectory)
            appendUInt32(0, to: &centralDirectory)
            appendUInt32(item.offset, to: &centralDirectory)
            centralDirectory.append(item.nameData)
        }

        archive.append(centralDirectory)

        appendUInt32(0x06054b50, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(0, to: &archive)
        appendUInt16(UInt16(entryOffsets.count), to: &archive)
        appendUInt16(UInt16(entryOffsets.count), to: &archive)
        appendUInt32(UInt32(centralDirectory.count), to: &archive)
        appendUInt32(centralOffset, to: &archive)
        appendUInt16(0, to: &archive)

        return archive
    }

    private static let crc32Table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crc32Table[idx]
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - PDF Report (Thread-Safe CoreGraphics + CoreText)

    static func buildPDF(request: ExportRequest, headers: [String], rows: [[String]]) -> Data {
        let output = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 792, height: 612)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        let margin: CGFloat = 36
        let contentWidth = mediaBox.width - margin * 2
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let navyColor = CGColor(colorSpace: colorSpace, components: [11 / 255, 37 / 255, 58 / 255, 1])!
        let secondaryColor = CGColor(colorSpace: colorSpace, components: [98 / 255, 111 / 255, 118 / 255, 1])!
        let zebraColor = CGColor(colorSpace: colorSpace, components: [245 / 255, 246 / 255, 247 / 255, 1])!
        let whiteColor = CGColor(colorSpace: colorSpace, components: [1, 1, 1, 1])!

        let titleFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 16, nil)
        let subtitleFont = CTFontCreateWithName("HelveticaNeue" as CFString, 9.5, nil)
        let headerFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 8.5, nil)
        let cellFont = CTFontCreateWithName("HelveticaNeue" as CFString, 8.0, nil)

        let visibleColCount = max(1, min(headers.count, 8))
        let visibleHeaders = Array(headers.prefix(visibleColCount))
        let colWidth = contentWidth / CGFloat(visibleColCount)
        let rowHeight: CGFloat = 22
        let headerHeight: CGFloat = 22

        func drawLine(_ text: String, x: CGFloat, baselineY: CGFloat, maxWidth: CGFloat, font: CTFont, color: CGColor) {
            let attrs: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: color,
            ]
            let attrStr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
            let fullLine = CTLineCreateWithAttributedString(attrStr)
            let width = CTLineGetTypographicBounds(fullLine, nil, nil, nil)
            let lineToDraw: CTLine
            if width > Double(maxWidth) {
                let ellipsisAttr = CFAttributedStringCreate(nil, "…" as CFString, attrs as CFDictionary)!
                let token = CTLineCreateWithAttributedString(ellipsisAttr)
                lineToDraw = CTLineCreateTruncatedLine(fullLine, Double(maxWidth), .end, token) ?? fullLine
            } else {
                lineToDraw = fullLine
            }
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: x, y: baselineY)
            CTLineDraw(lineToDraw, context)
        }

        let rowsPerPage = max(1, Int((mediaBox.height - 132) / rowHeight))
        let totalPages = max(1, Int(ceil(Double(max(rows.count, 1)) / Double(rowsPerPage))))

        for pageIndex in 0..<totalPages {
            context.beginPDFPage(nil)

            drawLine(
                "ADA Penyu · Sea Turtle Export Report",
                x: margin,
                baselineY: mediaBox.height - 46,
                maxWidth: contentWidth,
                font: titleFont,
                color: navyColor
            )
            let meta = "Scope: \(request.scope.title) · Range: \(request.range.title) · Records: \(rows.count) · Page \(pageIndex + 1) of \(totalPages)"
            drawLine(
                meta,
                x: margin,
                baselineY: mediaBox.height - 64,
                maxWidth: contentWidth,
                font: subtitleFont,
                color: secondaryColor
            )

            let headerBottomY = mediaBox.height - 100
            let headerRect = CGRect(x: margin, y: headerBottomY, width: contentWidth, height: headerHeight)
            context.setFillColor(navyColor)
            let headerPath = CGPath(roundedRect: headerRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
            context.addPath(headerPath)
            context.fillPath()

            for (idx, header) in visibleHeaders.enumerated() {
                drawLine(
                    header,
                    x: margin + CGFloat(idx) * colWidth + 6,
                    baselineY: headerBottomY + 7,
                    maxWidth: colWidth - 12,
                    font: headerFont,
                    color: whiteColor
                )
            }

            var currentRowBottomY = headerBottomY - 4 - rowHeight
            if rows.isEmpty {
                drawLine(
                    "No sea turtle records match the selected export scope and date range.",
                    x: margin + 6,
                    baselineY: currentRowBottomY + 7,
                    maxWidth: contentWidth - 12,
                    font: subtitleFont,
                    color: secondaryColor
                )
            } else {
                let start = pageIndex * rowsPerPage
                let end = min(start + rowsPerPage, rows.count)
                for (offset, row) in rows[start..<end].enumerated() {
                    if offset % 2 == 1 {
                        context.setFillColor(zebraColor)
                        context.fill(CGRect(x: margin, y: currentRowBottomY, width: contentWidth, height: rowHeight))
                    }
                    for colIdx in 0..<visibleColCount {
                        let text = colIdx < row.count ? row[colIdx] : ""
                        drawLine(
                            text,
                            x: margin + CGFloat(colIdx) * colWidth + 6,
                            baselineY: currentRowBottomY + 7,
                            maxWidth: colWidth - 12,
                            font: cellFont,
                            color: navyColor
                        )
                    }
                    currentRowBottomY -= rowHeight
                }
            }

            context.endPDFPage()
        }

        context.closePDF()
        return output as Data
    }
}
