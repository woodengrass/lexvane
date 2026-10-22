import ContentModel
import Foundation
#if os(macOS)
import PDFKit
#endif

public struct PDFExtractionFailure: Error, CustomStringConvertible {
    public let reason: String
    public let page: Int?
    public var description: String {
        "PDFExtractionFailure(reason=\(reason), page=\(page.map(String.init) ?? "unknown")); provide manual page references and reviewed parse rules; NO OCR performed"
    }
}
public struct PDFParseRule: Codable {
    public let version: String
    public let pattern: String
    public let termGroup: Int
    public let posGroup: Int
    public let levelGroup: Int
    public let ignoredPatterns: [String]
    public init(version: String, pattern: String, termGroup: Int, posGroup: Int, levelGroup: Int, ignoredPatterns: [String]) {
        self.version = version; self.pattern = pattern; self.termGroup = termGroup
        self.posGroup = posGroup; self.levelGroup = levelGroup; self.ignoredPatterns = ignoredPatterns
    }
    public static var fixtureTSV: Self {
        Self(version: "fixture-tsv-v1", pattern: "^([^\\t]+)\\t([^\\t]+)\\t([^\\t]+)$",
             termGroup: 1, posGroup: 2, levelGroup: 3, ignoredPatterns: [])
    }
}
public enum PDFExtractor {
    public static func extract(file: URL, rule: PDFParseRule) throws -> ExtractionAudit {
        guard file.isFileURL else { throw PDFExtractionFailure(reason: "explicit_local_file_required", page: nil) }
        #if os(macOS)
        let bytes: Data
        do { bytes = try Data(contentsOf: file) }
        catch { throw PDFExtractionFailure(reason: "file_read_failed", page: nil) }
        guard let document = PDFDocument(data: bytes), !document.isLocked, document.pageCount > 0 else {
            throw PDFExtractionFailure(reason: "invalid_pdf", page: nil)
        }
        let pages = (0..<document.pageCount).map { document.page(at: $0)?.string ?? "" }
        return try parse(pages: pages, materialHash: CKHash.sha256Hex(of: bytes), rule: rule)
        #else
        throw PDFExtractionFailure(reason: "macos_required", page: nil)
        #endif
    }
    public static func parse(pages: [String], materialHash: String, rule: PDFParseRule) throws -> ExtractionAudit {
        guard !pages.isEmpty, CKIdentityJSON.hashValid(materialHash), !rule.version.isEmpty else {
            throw PDFExtractionFailure(reason: "invalid_material_or_rule", page: nil)
        }
        let expression: NSRegularExpression
        let ignored: [NSRegularExpression]
        do {
            expression = try NSRegularExpression(pattern: rule.pattern)
            ignored = try rule.ignoredPatterns.map { try NSRegularExpression(pattern: $0) }
        } catch { throw PDFExtractionFailure(reason: "invalid_parse_regex", page: nil) }
        let groups = [rule.termGroup, rule.posGroup, rule.levelGroup]
        guard groups.allSatisfy({ $0 > 0 && $0 <= expression.numberOfCaptureGroups }), Set(groups).count == 3 else {
            throw PDFExtractionFailure(reason: "invalid_field_mapping", page: nil)
        }
        var items: [ExtractedItem] = []; var ignoredLines: [ExtractionLine] = []
        var lineCount = 0; var complete = true
        for (pageIndex, text) in pages.enumerated() {
            let page = pageIndex + 1
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PDFExtractionFailure(reason: "empty_page", page: page)
            }
            guard text.range(of: "[A-Za-z]", options: .regularExpression) != nil,
                  !text.unicodeScalars.contains(where: { $0.value == 0xfffd || (0xe000...0xf8ff).contains($0.value) ||
                      ($0.value < 32 && ![9, 10, 13].contains($0.value)) }) else {
                throw PDFExtractionFailure(reason: "garbled_page", page: page)
            }
            let lines = text.components(separatedBy: .newlines)
            for (lineIndex, raw) in lines.enumerated() {
                lineCount += 1
                let line = lineIndex + 1
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                if trimmed.isEmpty || ignored.contains(where: { $0.firstMatch(in: trimmed, range: range)?.range == range }) {
                    ignoredLines.append(ExtractionLine(page: page, line: line, text: raw, reason: "explicit_rule_ignored"))
                    continue
                }
                guard let match = expression.firstMatch(in: trimmed, range: range), match.range == range else {
                    complete = false
                    ignoredLines.append(ExtractionLine(page: page, line: line, text: raw, reason: "manual_line_review_required"))
                    continue
                }
                let fields = groups.compactMap { group -> String? in
                    guard let capture = Range(match.range(at: group), in: trimmed) else { return nil }
                    return String(trimmed[capture]).trimmingCharacters(in: .whitespaces)
                }
                guard fields.count == 3, fields.allSatisfy({ !$0.isEmpty }),
                      fields[0].range(of: "[A-Za-z]", options: .regularExpression) != nil else {
                    throw PDFExtractionFailure(reason: "empty_or_garbled_fields", page: page)
                }
                items.append(ExtractedItem(originalId: "p\(page):l\(line)", page: page, line: line,
                    term: fields[0], pos: fields[1], level: fields[2]))
            }
        }
        guard !items.isEmpty else { throw PDFExtractionFailure(reason: "no_parsed_items", page: nil) }
        return ExtractionAudit(contentHash: materialHash, parseRule: rule.version, pageCount: pages.count,
            lineCount: lineCount, items: items, ignoredLines: ignoredLines,
            fieldMapping: ["term", "pos", "level"], complete: complete)
    }
}
