import Foundation
import Testing
@testable import FinderV2

private final class EmptyShellMoveFileManager: FileManager {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try copyItem(at: srcURL, to: dstURL)
        let children = try contentsOfDirectory(
            at: srcURL,
            includingPropertiesForKeys: nil,
            options: []
        )
        for child in children {
            try removeItem(at: child)
        }
    }
}

private final class RecreatedFolderMoveFileManager: FileManager {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try copyItem(at: srcURL, to: dstURL)
        try removeItem(at: srcURL)

        let cache = srcURL
            .appendingPathComponent(".vite", isDirectory: true)
            .appendingPathComponent("deps", isDirectory: true)
        try createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("cache".utf8).write(
            to: cache.appendingPathComponent("_metadata.json")
        )
    }
}

private final class RecreatedEmptyFolderMoveFileManager: FileManager {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try copyItem(at: srcURL, to: dstURL)
        try removeItem(at: srcURL)
        try createDirectory(at: srcURL, withIntermediateDirectories: true)
    }
}

private final class PartialMoveErrorFileManager: FileManager {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try createDirectory(at: dstURL, withIntermediateDirectories: true)
        let firstChild = try contentsOfDirectory(
            at: srcURL,
            includingPropertiesForKeys: nil,
            options: []
        ).first
        if let firstChild {
            try copyItem(
                at: firstChild,
                to: dstURL.appendingPathComponent(firstChild.lastPathComponent)
            )
        }
        throw CocoaError(.fileWriteOutOfSpace)
    }
}

private final class NonEmptyResidualMoveFileManager: FileManager {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try copyItem(at: srcURL, to: dstURL)
        // Simulate a provider that reports success without removing the source.
    }
}

private final class ResidualFileMoveFileManager: FileManager {
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        try copyItem(at: srcURL, to: dstURL)
        // Simulate a provider that leaves the original file behind.
    }
}

@Suite("搬移完成檢查")
struct MoveCompletionTests {
    private func withTemporaryDirectory(_ work: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderV2MoveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try work(directory)
    }

    @Test("跨位置搬資料夾後會清走來源空殼")
    func moveRemovesEmptySourceShell() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let source = temporaryDirectory
                .appendingPathComponent("左", isDirectory: true)
                .appendingPathComponent("相片", isDirectory: true)
            let destination = temporaryDirectory
                .appendingPathComponent("右", isDirectory: true)
                .appendingPathComponent("相片", isDirectory: true)
            let nestedFile = source
                .appendingPathComponent("巢狀", isDirectory: true)
                .appendingPathComponent("內容.txt")

            try FileManager.default.createDirectory(
                at: nestedFile.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("完整內容".utf8).write(to: nestedFile)

            _ = try FileActionEngine.transfer(
                source: source,
                destination: destination,
                operation: .move,
                replaceExisting: false,
                fileManager: EmptyShellMoveFileManager(),
                directoryUseCheck: { _ in nil }
            )

            #expect(!FileManager.default.fileExists(atPath: source.path))
            #expect(
                try Data(
                    contentsOf: destination
                        .appendingPathComponent("巢狀", isDirectory: true)
                        .appendingPathComponent("內容.txt")
                ) == Data("完整內容".utf8)
            )
        }
    }

    @Test("舊位置被程式重新建立時會報錯而不刪隱藏檔")
    func recreatedSourceFolderIsPreservedAndReported() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let source = temporaryDirectory
                .appendingPathComponent("左", isDirectory: true)
                .appendingPathComponent("網站", isDirectory: true)
            let destination = temporaryDirectory
                .appendingPathComponent("右", isDirectory: true)
                .appendingPathComponent("網站", isDirectory: true)
            let originalFile = source.appendingPathComponent("index.html")

            try FileManager.default.createDirectory(
                at: source,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("<html></html>".utf8).write(to: originalFile)

            do {
                _ = try FileActionEngine.transfer(
                    source: source,
                    destination: destination,
                    operation: .move,
                    replaceExisting: false,
                    fileManager: RecreatedFolderMoveFileManager(),
                    directoryUseCheck: { _ in nil }
                )
                Issue.record("來源資料夾被重新建立時應該報錯")
            } catch FileOperationError.moveSourceRecreated {
                // Expected: never delete files recreated by another program.
            }

            #expect(
                FileManager.default.fileExists(
                    atPath: source
                        .appendingPathComponent(".vite/deps/_metadata.json")
                        .path
                )
            )
            #expect(
                FileManager.default.fileExists(
                    atPath: destination.appendingPathComponent("index.html").path
                )
            )
        }
    }

    @Test("普通資料夾連隱藏檔會完整搬走")
    func ordinaryFolderMoveIncludesHiddenFiles() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let source = temporaryDirectory
                .appendingPathComponent("左", isDirectory: true)
                .appendingPathComponent("網站", isDirectory: true)
            let destination = temporaryDirectory
                .appendingPathComponent("右", isDirectory: true)
                .appendingPathComponent("網站", isDirectory: true)

            try FileManager.default.createDirectory(
                at: source,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("secret".utf8).write(
                to: source.appendingPathComponent(".hidden")
            )

            _ = try FileActionEngine.transfer(
                source: source,
                destination: destination,
                operation: .move,
                replaceExisting: false,
                directoryUseCheck: { _ in nil }
            )

            #expect(!FileManager.default.fileExists(atPath: source.path))
            #expect(
                FileManager.default.fileExists(
                    atPath: destination.appendingPathComponent(".hidden").path
                )
            )
        }
    }

    @Test("另一個程式使用中時不會開始搬移")
    func folderInUseStopsBeforeMove() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let source = temporaryDirectory.appendingPathComponent("使用中", isDirectory: true)
            let destination = temporaryDirectory.appendingPathComponent("新位置", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try Data("原檔".utf8).write(to: source.appendingPathComponent("內容.txt"))
            try Data("舊目的地".utf8).write(
                to: destination.appendingPathComponent("舊內容.txt")
            )

            do {
                _ = try FileActionEngine.transfer(
                    source: source,
                    destination: destination,
                    operation: .move,
                    replaceExisting: true,
                    directoryUseCheck: { _ in "網站預覽程式" }
                )
                Issue.record("資料夾使用中時唔應該開始搬移")
            } catch FileOperationError.folderInUse("網站預覽程式") {
                // Expected.
            }

            #expect(FileManager.default.fileExists(atPath: source.path))
            #expect(
                FileManager.default.fileExists(
                    atPath: destination.appendingPathComponent("舊內容.txt").path
                )
            )
        }
    }

    @Test("另一個程式新建同名空資料夾亦不會被刪")
    func recreatedEmptyFolderIsPreserved() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let source = temporaryDirectory.appendingPathComponent("原資料夾", isDirectory: true)
            let destination = temporaryDirectory.appendingPathComponent("新資料夾", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("內容".utf8).write(to: source.appendingPathComponent("內容.txt"))

            do {
                _ = try FileActionEngine.transfer(
                    source: source,
                    destination: destination,
                    operation: .move,
                    replaceExisting: false,
                    fileManager: RecreatedEmptyFolderMoveFileManager(),
                    directoryUseCheck: { _ in nil }
                )
                Issue.record("新建同名空資料夾應該保留並報錯")
            } catch FileOperationError.moveSourceRecreated {
                // Expected.
            }

            #expect(FileManager.default.fileExists(atPath: source.path))
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    @Test("部分搬移後出錯不會被當成成功")
    func partialMoveErrorIsPreserved() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let source = temporaryDirectory.appendingPathComponent("來源", isDirectory: true)
            let destination = temporaryDirectory.appendingPathComponent("目的地", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("第一個".utf8).write(to: source.appendingPathComponent("一.txt"))
            try Data("第二個".utf8).write(to: source.appendingPathComponent("二.txt"))

            do {
                _ = try FileActionEngine.transfer(
                    source: source,
                    destination: destination,
                    operation: .move,
                    replaceExisting: false,
                    fileManager: PartialMoveErrorFileManager(),
                    directoryUseCheck: { _ in nil }
                )
                Issue.record("部分搬移出錯唔可以當成功")
            } catch {
                let cocoaError = error as NSError
                #expect(cocoaError.domain == NSCocoaErrorDomain)
                #expect(cocoaError.code == NSFileWriteOutOfSpaceError)
            }

            #expect(FileManager.default.fileExists(atPath: source.path))
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    @Test("來源仲有內容時只會保留並報錯")
    func nonEmptyResidualSourceIsNeverDeleted() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let source = temporaryDirectory.appendingPathComponent("來源", isDirectory: true)
            let destination = temporaryDirectory.appendingPathComponent("目的地", isDirectory: true)
            let original = source.appendingPathComponent("重要.txt")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("唔可以刪".utf8).write(to: original)

            do {
                _ = try FileActionEngine.transfer(
                    source: source,
                    destination: destination,
                    operation: .move,
                    replaceExisting: false,
                    fileManager: NonEmptyResidualMoveFileManager(),
                    directoryUseCheck: { _ in nil }
                )
                Issue.record("來源仲有內容時應該報錯")
            } catch FileOperationError.moveSourceNotRemoved {
                // Expected.
            }

            #expect(try Data(contentsOf: original) == Data("唔可以刪".utf8))
            #expect(
                try Data(
                    contentsOf: destination.appendingPathComponent("重要.txt")
                ) == Data("唔可以刪".utf8)
            )
        }
    }

    @Test("普通檔案搬完後原位置仲有檔案時會報錯")
    func residualFileIsNotReportedAsCompleted() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let source = temporaryDirectory.appendingPathComponent("重要.txt")
            let destination = temporaryDirectory
                .appendingPathComponent("右", isDirectory: true)
                .appendingPathComponent("重要.txt")
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("唔可以重複".utf8).write(to: source)

            do {
                _ = try FileActionEngine.transfer(
                    source: source,
                    destination: destination,
                    operation: .move,
                    replaceExisting: false,
                    fileManager: ResidualFileMoveFileManager(),
                    directoryUseCheck: { _ in nil }
                )
                Issue.record("來源檔案仍然存在時應該報錯")
            } catch FileOperationError.moveSourceNotRemoved {
                // Expected: both copies remain visible for manual inspection.
            }

            #expect(FileManager.default.fileExists(atPath: source.path))
            #expect(FileManager.default.fileExists(atPath: destination.path))
            #expect(try Data(contentsOf: source) == Data("唔可以重複".utf8))
            #expect(try Data(contentsOf: destination) == Data("唔可以重複".utf8))
        }
    }

    @Test("可以由 lsof 資料認出網站預覽程式")
    func lsofOutputIdentifiesPreviewProcess() {
        let path = "/tmp/網站"
        let output = """
        p8606
        cnode
        f21
        n\(path)
        """

        let name = DirectoryUseInspector.processName(
            fromLsofOutput: output,
            matchingPath: path,
            excludingPID: 999
        )

        #expect(name == "網站預覽程式")
    }
}
