import Foundation
import Testing
@testable import FinderV2

@Suite("Finder v2.0 檔案邏輯")
struct FileLogicTests {
    private func withTemporaryDirectory(_ work: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderV2Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try work(directory)
    }

    @Test("隱藏項目不顯示，資料夾排在前面")
    func fileListHidesHiddenItemsAndSortsFoldersFirst() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let folder = temporaryDirectory.appendingPathComponent("資料夾", isDirectory: true)
            let file = temporaryDirectory.appendingPathComponent("檔案.txt")
            let hidden = temporaryDirectory.appendingPathComponent(".秘密.txt")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data("hello".utf8).write(to: file)
            try Data("hidden".utf8).write(to: hidden)

            let items = try FileItem.load(from: temporaryDirectory)

            #expect(items.count == 2)
            #expect(items.first?.url.standardizedFileURL.path == folder.standardizedFileURL.path)
            #expect(!items.contains { $0.url == hidden })
        }
    }

    @Test("可以選擇顯示隱藏項目")
    func hiddenItemsCanBeShown() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let hidden = temporaryDirectory.appendingPathComponent(".秘密.txt")
            try Data("hidden".utf8).write(to: hidden)

            let items = try FileItem.load(from: temporaryDirectory, showHidden: true)

            #expect(items.contains { $0.url.lastPathComponent == ".秘密.txt" })
        }
    }

    @Test("左右比較分清獨有、相同及不同版本")
    func folderComparisonFindsDifferences() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let left = temporaryDirectory.appendingPathComponent("左", isDirectory: true)
            let right = temporaryDirectory.appendingPathComponent("右", isDirectory: true)
            try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
            try Data("same".utf8).write(to: left.appendingPathComponent("一樣.txt"))
            try Data("same".utf8).write(to: right.appendingPathComponent("一樣.txt"))
            try Data("left".utf8).write(to: left.appendingPathComponent("只在左.txt"))
            try Data("short".utf8).write(to: left.appendingPathComponent("唔同.txt"))
            try Data("much longer".utf8).write(to: right.appendingPathComponent("唔同.txt"))
            let date = Date(timeIntervalSince1970: 500)
            for url in [
                left.appendingPathComponent("一樣.txt"),
                right.appendingPathComponent("一樣.txt")
            ] {
                try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            }

            let result = FolderComparisonEngine.compare(
                left: try FileItem.load(from: left),
                right: try FileItem.load(from: right)
            )

            #expect(result.left["只在左.txt"] == .onlyHere)
            #expect(result.left["一樣.txt"] == .same)
            #expect(result.left["唔同.txt"] == .different)
        }
    }

    @Test("批量改名會保留副檔名")
    func batchRenameKeepsExtensions() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let firstURL = temporaryDirectory.appendingPathComponent("相片.jpg")
            let secondURL = temporaryDirectory.appendingPathComponent("文件.pdf")
            try Data().write(to: firstURL)
            try Data().write(to: secondURL)
            let items = [FileItem.loadItem(at: firstURL), FileItem.loadItem(at: secondURL)].compactMap { $0 }

            let names = BatchRenameEngine.proposedNames(
                for: items,
                mode: .number,
                firstText: "旅行-"
            )

            #expect(names == ["旅行-1.jpg", "旅行-2.pdf"])
        }
    }

    @Test("ZIP 可以壓縮及解壓")
    func zipRoundTrip() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let source = temporaryDirectory.appendingPathComponent("內容.txt")
            try Data("Finder v2.0".utf8).write(to: source)
            let zip = try ArchiveEngine.createZip(
                from: [source],
                in: temporaryDirectory,
                named: "測試"
            )
            let extractedFolder = try ArchiveEngine.extractZip(zip, to: temporaryDirectory)

            #expect(FileManager.default.fileExists(atPath: zip.path))
            #expect(
                FileManager.default.fileExists(
                    atPath: extractedFolder.appendingPathComponent("內容.txt").path
                )
            )
        }
    }

    @Test("保留兩個會使用下一個可用名稱")
    func keepBothNameUsesNextAvailableNumber() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let original = temporaryDirectory.appendingPathComponent("報告.pdf")
            let second = temporaryDirectory.appendingPathComponent("報告 2.pdf")
            try Data().write(to: original)
            try Data().write(to: second)

            let available = FileTransferCoordinator.availableURL(for: original)

            #expect(available.lastPathComponent == "報告 3.pdf")
        }
    }

    @Test("常用位置包括四個主要資料夾")
    func sidebarAlwaysIncludesMainFolders() {
        let titles = Set(SidebarLocationProvider.locations().map(\.title))

        #expect(titles.contains("主目錄"))
        #expect(titles.contains("桌面"))
        #expect(titles.contains("文件"))
        #expect(titles.contains("下載項目"))
    }

    @Test("搬移後原本位置不再有檔案")
    func moveTransferMovesTheFile() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let sourceFolder = temporaryDirectory.appendingPathComponent("左", isDirectory: true)
            let destinationFolder = temporaryDirectory.appendingPathComponent("右", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            let source = sourceFolder.appendingPathComponent("搬移測試.txt")
            let destination = destinationFolder.appendingPathComponent("搬移測試.txt")
            try Data("move".utf8).write(to: source)

            _ = try FileActionEngine.transfer(
                source: source,
                destination: destination,
                operation: .move,
                replaceExisting: false
            )

            #expect(!FileManager.default.fileExists(atPath: source.path))
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    @Test("複製後原本位置仍然有檔案")
    func copyTransferKeepsTheOriginal() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let sourceFolder = temporaryDirectory.appendingPathComponent("左", isDirectory: true)
            let destinationFolder = temporaryDirectory.appendingPathComponent("右", isDirectory: true)
            try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            let source = sourceFolder.appendingPathComponent("複製測試.txt")
            let destination = destinationFolder.appendingPathComponent("複製測試.txt")
            try Data("copy".utf8).write(to: source)

            _ = try FileActionEngine.transfer(
                source: source,
                destination: destination,
                operation: .copy,
                replaceExisting: false
            )

            #expect(FileManager.default.fileExists(atPath: source.path))
            #expect(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    @Test("中間分隔線可以向左及向右移動")
    @MainActor
    func mainDividerMovesInBothDirections() {
        let controller = MainViewController()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1_200, height: 700)
        controller.view.layoutSubtreeIfNeeded()
        controller.mainSplitView.adjustSubviews()

        controller.mainSplitView.setPosition(360, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        let leftNarrowWidth = controller.mainSplitView.subviews[0].frame.width

        controller.mainSplitView.setPosition(760, ofDividerAt: 0)
        controller.view.layoutSubtreeIfNeeded()
        let leftWideWidth = controller.mainSplitView.subviews[0].frame.width

        #expect(leftNarrowWidth < 430)
        #expect(leftWideWidth > 700)
        #expect(leftWideWidth > leftNarrowWidth)
    }

    @Test("可以切換所有雙開、三開及四開版面")
    @MainActor
    func allPaneLayoutsCanBeBuilt() {
        let previous = UserDefaults.standard.object(forKey: MainViewController.layoutDefaultsKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: MainViewController.layoutDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: MainViewController.layoutDefaultsKey)
            }
        }
        UserDefaults.standard.set(PaneLayout.sideBySide.rawValue, forKey: MainViewController.layoutDefaultsKey)
        let controller = MainViewController()
        controller.view.frame = NSRect(x: 0, y: 0, width: 1_380, height: 820)

        for layout in PaneLayout.allCases {
            controller.applyLayout(layout)
            controller.view.layoutSubtreeIfNeeded()
            #expect(controller.currentLayout == layout)
            #expect(controller.visiblePaneCount == layout.paneCount)
            #expect(controller.mainSplitView.subviews.count >= 2)
        }
    }

    @Test("搜尋及日期排列會保留資料夾在前面")
    func searchAndSortingArrangeItems() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let folder = temporaryDirectory.appendingPathComponent("報告資料夾", isDirectory: true)
            let oldFile = temporaryDirectory.appendingPathComponent("報告 舊.txt")
            let newFile = temporaryDirectory.appendingPathComponent("報告 新.txt")
            let ignored = temporaryDirectory.appendingPathComponent("相片.png")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try Data("old".utf8).write(to: oldFile)
            try Data("new".utf8).write(to: newFile)
            try Data("photo".utf8).write(to: ignored)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 100)],
                ofItemAtPath: oldFile.path
            )
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 200)],
                ofItemAtPath: newFile.path
            )

            let loaded = try FileItem.load(from: temporaryDirectory)
            let arranged = FileDisplayArrangement.items(
                from: loaded,
                matching: "報告",
                sortedBy: .modified,
                ascending: false
            )

            #expect(arranged.map(\.name) == ["報告資料夾", "報告 新.txt", "報告 舊.txt"])
        }
    }

    @Test("複製大檔案會報告進度")
    func copyReportsProgress() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let source = temporaryDirectory.appendingPathComponent("來源.bin")
            let destination = temporaryDirectory.appendingPathComponent("副本.bin")
            let data = Data(repeating: 7, count: 2_500_000)
            try data.write(to: source)
            var reportedBytes: Int64 = 0

            _ = try FileActionEngine.transfer(
                source: source,
                destination: destination,
                operation: .copy,
                replaceExisting: false,
                progress: { reportedBytes += $0 },
                isCancelled: { false }
            )

            #expect(reportedBytes == Int64(data.count))
            #expect(try Data(contentsOf: destination) == data)
        }
    }

    @Test("取消複製不會留下半個檔案")
    func cancelledCopyLeavesNoPartialFile() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let source = temporaryDirectory.appendingPathComponent("來源.bin")
            let destination = temporaryDirectory.appendingPathComponent("未完成.bin")
            try Data(repeating: 3, count: 1_500_000).write(to: source)

            do {
                _ = try FileActionEngine.transfer(
                    source: source,
                    destination: destination,
                    operation: .copy,
                    replaceExisting: false,
                    progress: { _ in },
                    isCancelled: { true }
                )
                Issue.record("應該要取消複製")
            } catch FileOperationError.cancelled {
                // Expected.
            }

            #expect(!FileManager.default.fileExists(atPath: destination.path))
            #expect(FileManager.default.fileExists(atPath: source.path))
        }
    }
}
