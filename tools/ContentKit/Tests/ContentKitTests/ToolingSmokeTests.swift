import Foundation
import XCTest

/// Smoke tests for the isolated ContentKit tooling (Task 1).
/// Uses a subprocess harness via the Xcode toolchain: expected rejections must
/// exit non-zero with a typed reason. Never swallows errors with `|| true`.
final class ToolingSmokeTests: XCTestCase {
    private static var packagePath: String {
        let thisFile = URL(fileURLWithPath: #filePath)
        // .../tools/ContentKit/Tests/ContentKitTests/ToolingSmokeTests.swift
        // -> package root is 3 levels up from this file.
        return thisFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    private static var repoRoot: String {
        URL(fileURLWithPath: packagePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    @discardableResult
    private static func runContentKit(_ args: [String]) throws -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var env = ProcessInfo.processInfo.environment
        env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
        // The child `swift run` takes a per-package lock under TMPDIR. When these
        // tests themselves run under `swift test`, the outer runner holds that
        // same lock for the whole session, so the child would block forever.
        // A private TMPDIR keeps the real `swift run` subprocess while avoiding
        // the self-deadlock. The shared package build cache is still reused.
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("contentkit-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        env["TMPDIR"] = scratch.path.hasSuffix("/") ? scratch.path : scratch.path + "/"
        process.environment = env
        process.arguments = ["xcrun", "swift", "run", "--package-path", packagePath, "contentkit"] + args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    func testHelpExitsZeroWithUsage() throws {
        let (code, output) = try Self.runContentKit(["--help"])
        XCTAssertEqual(code, 0, "expected exit 0 for --help. Output:\n\(output)")
        XCTAssertTrue(output.contains("Usage: contentkit"), "help must print usage. Output:\n\(output)")
    }

    func testUnknownCommandFails() throws {
        let (code, output) = try Self.runContentKit(["frobnicate-unknown-cmd"])
        XCTAssertNotEqual(code, 0, "unknown command must exit non-zero. Output:\n\(output)")
        XCTAssertTrue(
            output.contains("unknown command") || output.contains("CKError"),
            "unknown command must print a typed reason. Output:\n\(output)"
        )
    }

    func testEmptyCommandFails() throws {
        let (code, output) = try Self.runContentKit([])
        XCTAssertNotEqual(code, 0, "empty command must exit non-zero. Output:\n\(output)")
        XCTAssertTrue(
            output.contains("no command") || output.contains("CKError") || output.contains("Usage"),
            "empty command must print a typed reason or usage. Output:\n\(output)"
        )
    }

    func testDoesNotMutateAppFiles() throws {
        let fm = FileManager.default
        let probe = URL(fileURLWithPath: Self.repoRoot).appendingPathComponent("Lexvane/LexvaneApp.swift")
        let attrsBefore = try fm.attributesOfItem(atPath: probe.path)
        let mtimeBefore = attrsBefore[.modificationDate] as? Date
        let hashBefore = try Self.sha256Hex(ofFileAt: probe.path)

        let (code, _) = try Self.runContentKit(["--help"])
        XCTAssertEqual(code, 0)

        let attrsAfter = try fm.attributesOfItem(atPath: probe.path)
        let mtimeAfter = attrsAfter[.modificationDate] as? Date
        let hashAfter = try Self.sha256Hex(ofFileAt: probe.path)
        XCTAssertEqual(hashBefore, hashAfter, "CLI must not mutate Lexvane target files")
        XCTAssertEqual(mtimeBefore, mtimeAfter, "CLI must not touch Lexvane target mtimes")
    }

    private static func sha256Hex(ofFileAt path: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        process.arguments = ["-a", "256", path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return String(text.split(separator: " ").first ?? "")
    }
}
