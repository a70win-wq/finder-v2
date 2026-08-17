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

    @Test("大小寫不同的檔名會分開比較及同步")
    func folderComparisonRespectsFileNameCase() {
        let leftItem = FileItem(
            url: URL(fileURLWithPath: "/tmp/FinderV2-left/Report.txt"),
            isDirectory: false,
            isPackage: false,
            fileSize: 10,
            modifiedDate: Date(timeIntervalSince1970: 500),
            kind: "文稿"
        )
        let rightItem = FileItem(
            url: URL(fileURLWithPath: "/tmp/FinderV2-right/report.txt"),
            isDirectory: false,
            isPackage: false,
            fileSize: 10,
            modifiedDate: Date(timeIntervalSince1970: 500),
            kind: "文稿"
        )

        let result = FolderComparisonEngine.compare(left: [leftItem], right: [rightItem])

        #expect(result.left["Report.txt"] == .onlyHere)
        #expect(result.right["report.txt"] == .onlyHere)
        #expect(FolderComparisonEngine.syncSources(from: [leftItem], to: [rightItem]) == [leftItem.url])
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

        #expect(titles.contains(L("主目錄")))
        #expect(titles.contains(L("桌面")))
        #expect(titles.contains(L("文件")))
        #expect(titles.contains(L("下載項目")))
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

        controller.mainSplitView.onWillResize?()
        controller.mainSplitView.setPosition(360, ofDividerAt: 0)
        controller.mainSplitView.onDidResize?()
        controller.view.layoutSubtreeIfNeeded()
        let leftNarrowWidth = controller.mainSplitView.subviews[0].frame.width

        controller.mainSplitView.onWillResize?()
        controller.mainSplitView.setPosition(760, ofDividerAt: 0)
        controller.mainSplitView.onDidResize?()
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

    @Test("載入時一次過計好顯示名稱")
    func loadStoresDisplayNameOnce() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let file = temporaryDirectory.appendingPathComponent("測試.txt")
            try Data("hello".utf8).write(to: file)

            let items = try FileItem.load(from: temporaryDirectory)
            let item = try #require(items.first { $0.url.lastPathComponent == "測試.txt" })

            #expect(item.name == "測試.txt")
            #expect(item.storedName == "測試.txt")
        }
    }

    @Test("已按名稱排序嘅來源可以跳過第二次排序")
    func presortedSourceSkipsSecondSortPass() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderV2Presort", isDirectory: true)
        func makeItem(_ name: String, isDirectory: Bool = false) -> FileItem {
            FileItem(
                url: base.appendingPathComponent(name),
                isDirectory: isDirectory,
                isPackage: false,
                fileSize: 1,
                modifiedDate: Date(timeIntervalSince1970: 100),
                kind: "檔案"
            )
        }
        let unsorted: [FileItem] = [
            makeItem("Bravo.txt"),
            makeItem("Alpha.txt"),
            makeItem("Zzz 資料夾", isDirectory: true)
        ]

        // 聲稱已經排好：原樣保留，唔再排多次
        let withFlag = FileDisplayArrangement.items(
            from: unsorted,
            matching: "",
            sortedBy: .name,
            ascending: true,
            sourceIsPresortedByNameAscending: true
        )
        #expect(withFlag.map(\.name) == ["Bravo.txt", "Alpha.txt", "Zzz 資料夾"])

        // 冇聲稱：照常排序（資料夾在前、名稱升序）
        let withoutFlag = FileDisplayArrangement.items(
            from: unsorted,
            matching: "",
            sortedBy: .name,
            ascending: true
        )
        #expect(withoutFlag.map(\.name) == ["Zzz 資料夾", "Alpha.txt", "Bravo.txt"])
    }

    @Test("收藏改動會令側邊欄快取失效")
    func sidebarCacheInvalidatesWhenFavoritesChange() throws {
        let entriesKey = "FinderV2FavoriteEntriesV2"
        let legacyKey = "FinderV2FavoriteFolders"
        let previousEntries = UserDefaults.standard.object(forKey: entriesKey)
        let previousLegacy = UserDefaults.standard.object(forKey: legacyKey)
        defer {
            if let previousEntries {
                UserDefaults.standard.set(previousEntries, forKey: entriesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: entriesKey)
            }
            if let previousLegacy {
                UserDefaults.standard.set(previousLegacy, forKey: legacyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: legacyKey)
            }
            SidebarLocationProvider.invalidateCachedLocations()
        }
        UserDefaults.standard.removeObject(forKey: entriesKey)
        UserDefaults.standard.removeObject(forKey: legacyKey)
        SidebarLocationProvider.invalidateCachedLocations()

        let before = SidebarLocationProvider.locations()
        #expect(!before.contains { $0.isFavorite })

        try withTemporaryDirectory { temporaryDirectory in
            FavoriteStore.shared.add(temporaryDirectory)

            let after = SidebarLocationProvider.locations()
            #expect(
                after.contains {
                    $0.url.standardizedFileURL == temporaryDirectory.standardizedFileURL
                }
            )
        }
    }

    @Test("重複載入相同內容唔會整亂清單")
    @MainActor
    func reloadingIdenticalItemsKeepsTableInSync() throws {
        let controller = FileTableViewController()
        _ = controller.view
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderV2ReloadSync", isDirectory: true)
        func makeItem(_ name: String) -> FileItem {
            FileItem(
                url: base.appendingPathComponent(name),
                isDirectory: false,
                isPackage: false,
                fileSize: 1,
                modifiedDate: Date(timeIntervalSince1970: 100),
                kind: "檔案"
            )
        }
        let items = [makeItem("Alpha.txt"), makeItem("Bravo.txt")]
        let directory = URL(fileURLWithPath: "/tmp")

        controller.reload(items: items, currentDirectory: directory)
        #expect(controller.tableView.numberOfRows == items.count)
        #expect(controller.items.count == items.count)

        // 相同內容再載入：行數保持、唔會整亂
        controller.reload(items: items, currentDirectory: directory)
        #expect(controller.tableView.numberOfRows == items.count)

        // 內容有變就正常更新
        let updated = items + [makeItem("Charlie.png")]
        controller.reload(items: updated, currentDirectory: directory)
        #expect(controller.tableView.numberOfRows == updated.count)
        #expect(controller.items.count == updated.count)
    }

    @Test("讀取單一隱藏檔唔會當佢唔存在")
    func loadItemKeepsHiddenFiles() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let hidden = temporaryDirectory.appendingPathComponent(".秘密.txt")
            try Data("hidden".utf8).write(to: hidden)

            let item = FileItem.loadItem(at: hidden)
            #expect(item?.url.lastPathComponent == ".秘密.txt")
        }
    }

    @Test("比較唔會因為顯示名稱相同而崩潰")
    func comparisonDoesNotCrashOnDuplicateDisplayNames() {
        let left = [
            FileItem(
                url: URL(fileURLWithPath: "/tmp/a/file.txt"),
                isDirectory: false,
                isPackage: false,
                fileSize: 1,
                modifiedDate: Date(timeIntervalSince1970: 100),
                kind: "文稿",
                storedName: "file"
            ),
            FileItem(
                url: URL(fileURLWithPath: "/tmp/a/file.pdf"),
                isDirectory: false,
                isPackage: false,
                fileSize: 2,
                modifiedDate: Date(timeIntervalSince1970: 100),
                kind: "PDF",
                storedName: "file"
            )
        ]
        let result = FolderComparisonEngine.compare(left: left, right: [])
        #expect(result.leftOnlyCount == 2)
        #expect(result.left["file.txt"] == .onlyHere)
        #expect(result.left["file.pdf"] == .onlyHere)
    }

    @Test("點檔批量改名會保留完整名稱")
    func batchRenameKeepsDotfileName() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let gitignore = temporaryDirectory.appendingPathComponent(".gitignore")
            try Data().write(to: gitignore)
            let item = try #require(FileItem.loadItem(at: gitignore))

            let names = BatchRenameEngine.proposedNames(
                for: [item],
                mode: .prefix,
                firstText: "bak-"
            )

            #expect(names == ["bak-.gitignore"])
        }
    }

    @Test("套件批量改名會保留副檔名")
    func batchRenameKeepsPackageExtension() {
        let item = FileItem(
            url: URL(fileURLWithPath: "/tmp/Safari.app"),
            isDirectory: true,
            isPackage: true,
            fileSize: nil,
            modifiedDate: nil,
            kind: "應用程式"
        )
        let names = BatchRenameEngine.proposedNames(
            for: [item],
            mode: .prefix,
            firstText: "舊-"
        )
        #expect(names == ["舊-Safari.app"])
    }

    @Test("批量改名失敗會還原原本檔名")
    func batchRenameRollsBackOnFailure() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let first = temporaryDirectory.appendingPathComponent("一.txt")
            let second = temporaryDirectory.appendingPathComponent("二.txt")
            try Data("1".utf8).write(to: first)
            try Data("2".utf8).write(to: second)
            let blocker = temporaryDirectory.appendingPathComponent("新二.txt", isDirectory: true)
            try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: blocker.appendingPathComponent("inside.txt"))
            let items = [FileItem.loadItem(at: first), FileItem.loadItem(at: second)].compactMap { $0 }

            do {
                _ = try BatchRenameEngine.apply(
                    items: items,
                    names: ["新一.txt", "新二.txt"]
                )
                Issue.record("應該要因為目標係資料夾而失敗")
            } catch {
                // Expected.
            }

            #expect(FileManager.default.fileExists(atPath: first.path))
            #expect(FileManager.default.fileExists(atPath: second.path))
            #expect(
                !(try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
                    .contains { $0.hasPrefix(".FinderV2Rename-") })
            )
        }
    }

    @Test("ZIP 可以壓縮子資料夾入面嘅檔案")
    func zipUsesRelativePathForNestedFiles() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let nested = temporaryDirectory.appendingPathComponent("相簿", isDirectory: true)
            try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
            let source = nested.appendingPathComponent("相片.txt")
            try Data("photo".utf8).write(to: source)

            #expect(
                ArchiveEngine.zipEntryPath(for: source, in: temporaryDirectory) == "相簿/相片.txt"
            )

            let zip = try ArchiveEngine.createZip(
                from: [source],
                in: temporaryDirectory,
                named: "相簿壓縮"
            )
            let extracted = try ArchiveEngine.extractZip(zip, to: temporaryDirectory)
            #expect(
                FileManager.default.fileExists(
                    atPath: extracted.appendingPathComponent("相簿/相片.txt").path
                )
            )
        }
    }

    @Test("同一個批次兩個同名檔會保留兩個")
    func batchTransferKeepsBothSameNames() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let left = temporaryDirectory.appendingPathComponent("左", isDirectory: true)
            let right = temporaryDirectory.appendingPathComponent("右", isDirectory: true)
            let dest = temporaryDirectory.appendingPathComponent("目的地", isDirectory: true)
            try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            let first = left.appendingPathComponent("相片.jpg")
            let second = right.appendingPathComponent("相片.jpg")
            try Data("a".utf8).write(to: first)
            try Data("b".utf8).write(to: second)

            var reserved = Set<String>()
            var remembered: CollisionChoice? = .keepBoth
            let requests = FileTransferCoordinator.planRequests(
                sources: [first, second],
                destinationFolder: dest,
                operation: .copy,
                reservedPaths: &reserved,
                rememberedChoice: &remembered,
                askCollision: { _ in (.keepBoth, true) }
            )

            #expect(requests.count == 2)
            #expect(Set(requests.map(\.destination.lastPathComponent)) == ["相片.jpg", "相片 2.jpg"])
        }
    }

    @Test("未掛載嘅收藏唔會因為新增另一個而消失")
    func missingFavoritesSurviveLaterEdits() throws {
        let entriesKey = "FinderV2FavoriteEntriesV2"
        let legacyKey = "FinderV2FavoriteFolders"
        let previousEntries = UserDefaults.standard.object(forKey: entriesKey)
        let previousLegacy = UserDefaults.standard.object(forKey: legacyKey)
        defer {
            if let previousEntries {
                UserDefaults.standard.set(previousEntries, forKey: entriesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: entriesKey)
            }
            if let previousLegacy {
                UserDefaults.standard.set(previousLegacy, forKey: legacyKey)
            } else {
                UserDefaults.standard.removeObject(forKey: legacyKey)
            }
            SidebarLocationProvider.invalidateCachedLocations()
        }
        UserDefaults.standard.removeObject(forKey: entriesKey)
        UserDefaults.standard.removeObject(forKey: legacyKey)

        try withTemporaryDirectory { existing in
            let missing = FileManager.default.temporaryDirectory
                .appendingPathComponent("FinderV2-MissingFav-\(UUID().uuidString)", isDirectory: true)
            FavoriteStore.shared.add(missing)
            FavoriteStore.shared.add(existing)

            #expect(FavoriteStore.shared.storedEntries.contains { $0.path == missing.path })
            #expect(!FavoriteStore.shared.entries.contains { $0.path == missing.path })
            #expect(FavoriteStore.shared.entries.contains { $0.path == existing.path })
        }
    }

    @Test("資料夾內容唔同時比較會標成唔同")
    func comparisonRecursesIntoFolders() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let left = temporaryDirectory.appendingPathComponent("左", isDirectory: true)
            let right = temporaryDirectory.appendingPathComponent("右", isDirectory: true)
            let leftPhotos = left.appendingPathComponent("相簿", isDirectory: true)
            let rightPhotos = right.appendingPathComponent("相簿", isDirectory: true)
            try FileManager.default.createDirectory(at: leftPhotos, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: rightPhotos, withIntermediateDirectories: true)
            try Data("a".utf8).write(to: leftPhotos.appendingPathComponent("a.txt"))
            try Data("b".utf8).write(to: rightPhotos.appendingPathComponent("b.txt"))

            let result = FolderComparisonEngine.compare(
                left: try FileItem.load(from: left),
                right: try FileItem.load(from: right)
            )
            #expect(result.left["相簿"] == .different)
        }
    }

    @Test("同一個 inode 唔會當係另一個檔")
    func caseOnlyRenameIsSameItem() throws {
        try withTemporaryDirectory { temporaryDirectory in
            let original = temporaryDirectory.appendingPathComponent("Photo.JPG")
            try Data("img".utf8).write(to: original)
            let destination = temporaryDirectory.appendingPathComponent("Photo.jpg")

            if FileManager.default.fileExists(atPath: destination.path) {
                #expect(FileRenameSupport.isSameItem(original, as: destination))
                #expect(!FileRenameSupport.existsAsDifferentItem(destination, source: original))
            }
        }
    }
}
