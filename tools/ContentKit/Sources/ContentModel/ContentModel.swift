import CryptoKit
import Foundation

/// Stable helpers for the isolated content tooling (Task 1).
/// Foundation/CryptoKit only — never SwiftUI/UIKit/PDFKit.

/// Deterministic SHA-256 helpers. No timestamps or absolute paths are mixed in.
public enum CKHash {
    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(ofFileAt url: URL) throws -> String {
        try sha256Hex(of: Data(contentsOf: url))
    }
}

/// Minimal UTF-8 JSONL helpers with explicit paths (no hidden CWD reads).
public enum CKJSONL {
    public static func readLines(at url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    public static func appendLine(_ line: String, to url: URL) throws {
        let manager = FileManager.default
        if !manager.fileExists(atPath: url.path) {
            manager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        guard let data = (line + "\n").data(using: .utf8) else { return }
        try handle.write(contentsOf: data)
    }

    /// Canonical single-line JSON for stable hashes (sorted keys, UTF-8).
    public static func canonicalJSON(_ value: [String: String]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// Explicit path helpers. Callers pass every path via flags; nothing is inferred.
public enum CKPaths {
    public static func ensureDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
