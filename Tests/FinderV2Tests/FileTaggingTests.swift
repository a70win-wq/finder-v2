import Foundation
import Testing
@testable import FinderV2

@Suite("Finder v2.0 標籤")
struct FileTaggingTests {
    @Test("可以加入及清除 Finder 顏色標籤")
    func addAndRemoveFinderTag() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderV2Tag-\(UUID().uuidString).txt")
        try Data("test".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try FileTagEngine.apply(.red, to: [fileURL])
        let storedTags = try readStoredTags(at: fileURL)
        #expect(storedTags == [FinderTag.red.metadataValue])

        try FileTagEngine.apply(nil, to: [fileURL])
        #expect(try readStoredTagsIfPresent(at: fileURL) == nil)
    }

    @Test("複製普通檔案會保留顏色標籤")
    func copyPreservesFinderTags() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderV2TagCopy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("來源.txt")
        let destination = directory.appendingPathComponent("副本.txt")
        try Data("tagged".utf8).write(to: source)
        try FileTagEngine.apply(.blue, to: [source])

        _ = try FileActionEngine.transfer(
            source: source,
            destination: destination,
            operation: .copy,
            replaceExisting: false,
            progress: { _ in },
            isCancelled: { false }
        )

        #expect(try readStoredTags(at: destination) == [FinderTag.blue.metadataValue])
    }

    private func readStoredTags(at url: URL) throws -> [String] {
        guard let tags = try readStoredTagsIfPresent(at: url) else {
            throw NSError(
                domain: "FinderV2Tests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "搵唔到標籤"]
            )
        }
        return tags
    }

    private func readStoredTagsIfPresent(at url: URL) throws -> [String]? {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = [
            "-px",
            "com.apple.metadata:_kMDItemUserTags",
            url.path
        ]
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?
            .filter { !$0.isWhitespace } ?? ""
        var data = Data()
        var index = output.startIndex
        while index < output.endIndex {
            let nextIndex = output.index(index, offsetBy: 2)
            guard let byte = UInt8(output[index..<nextIndex], radix: 16) else {
                return nil
            }
            data.append(byte)
            index = nextIndex
        }
        return try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String]
    }
}
