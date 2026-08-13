import AppKit
import Foundation
import Testing
@testable import FinderV2

@Suite("Finder v2.0 右鍵選單")
struct ContextMenuTests {
    @Test("空白位置顯示資料夾、貼上、顯示及排列功能")
    func backgroundMenuPlan() {
        let plan = FileContextMenuPlan.make(
            selectionCount: 0,
            containsZip: false,
            containsCloudItem: false,
            clipboardHasFiles: false
        )

        #expect(plan.items == [
            FileContextMenuPlanItem(.newFolder),
            FileContextMenuPlanItem(.paste, isEnabled: false),
            FileContextMenuPlanItem(.separator),
            FileContextMenuPlanItem(.viewMode),
            FileContextMenuPlanItem(.sort),
            FileContextMenuPlanItem(.showViewOptions),
            FileContextMenuPlanItem(.toggleHiddenFiles)
        ])
    }

    @Test("揀選檔案後顯示完整 Finder 式功能")
    func selectedMenuPlan() {
        let plan = FileContextMenuPlan.make(
            selectionCount: 2,
            containsZip: true,
            containsCloudItem: true,
            clipboardHasFiles: false
        )
        let commands = plan.items.map(\.command)

        #expect(commands.contains(.folderWithSelection))
        #expect(commands.contains(.open))
        #expect(commands.contains(.openWith))
        #expect(commands.contains(.trash))
        #expect(commands.contains(.info))
        #expect(commands.contains(.rename))
        #expect(commands.contains(.compress))
        #expect(commands.contains(.duplicate))
        #expect(commands.contains(.alias))
        #expect(commands.contains(.preview))
        #expect(commands.contains(.copy))
        #expect(commands.contains(.share))
        #expect(commands.contains(.tags))
        #expect(commands.contains(.showViewOptions))
        #expect(commands.contains(.extractZip))
        #expect(commands.contains(.cloudDownload))
        #expect(commands.contains(.copyPath))
        #expect(commands.contains(.revealInFinder))
        #expect(!commands.contains(.newFolder))
        #expect(!commands.contains(.paste))
    }

    @Test("空白位置冇檔案可貼上時貼上會變灰")
    @MainActor
    func backgroundPasteStateAndTitles() {
        let controller = FileTableViewController()
        _ = controller.view
        controller.reload(
            items: [],
            currentDirectory: FileManager.default.temporaryDirectory
        )

        let titles = controller.contextMenuTitlesForTesting(
            clipboardHasFiles: false
        )

        #expect(titles == [
            "新增資料夾",
            "貼上項目",
            "—",
            "顯示方式",
            "排列方式",
            "顯示選項…",
            "顯示隱藏檔案"
        ])
        #expect(
            controller.contextMenuItemIsEnabledForTesting(
                title: "貼上項目",
                clipboardHasFiles: false
            ) == false
        )
        #expect(
            controller.contextMenuItemIsEnabledForTesting(
                title: "貼上項目",
                clipboardHasFiles: true
            ) == true
        )

        let disabledPlan = FileContextMenuPlan.make(
            selectionCount: 0,
            containsZip: false,
            containsCloudItem: false,
            clipboardHasFiles: false
        )
        let enabledPlan = FileContextMenuPlan.make(
            selectionCount: 0,
            containsZip: false,
            containsCloudItem: false,
            clipboardHasFiles: true
        )
        #expect(disabledPlan.items[1].command == .paste)
        #expect(!disabledPlan.items[1].isEnabled)
        #expect(enabledPlan.items[1].isEnabled)
    }

    @Test("側邊欄右鍵顯示開啟、拷貝、路徑及資料選項")
    @MainActor
    func sidebarContextMenuTitles() {
        let directory = FileManager.default.temporaryDirectory
        let controller = SidebarViewController(
            locationProvider: {
                [SidebarLocation(
                    title: "測試資料夾",
                    url: directory,
                    symbolName: "folder"
                )]
            }
        )
        _ = controller.view

        #expect(controller.contextMenuTitlesForTesting(at: 0) == [
            "開啟",
            "在 Apple Finder 顯示",
            "拷貝「測試資料夾」",
            "複製路徑",
            "—",
            "取得資料",
            "加入收藏"
        ])
    }

    @Test("Google Drive 右鍵顯示狀態、管理及取消顯示")
    @MainActor
    func googleDriveSidebarContextMenuTitles() {
        let directory = FileManager.default.temporaryDirectory
        let controller = SidebarViewController(
            locationProvider: {
                [SidebarLocation(
                    title: "舊 Google Drive",
                    url: directory,
                    symbolName: "externaldrive.badge.icloud",
                    isCloudStorage: true,
                    isFileProviderBacked: false,
                    cloudProviderBundleIdentifier: "com.google.drivefs"
                )]
            }
        )
        _ = controller.view

        let titles = controller.contextMenuTitlesForTesting(at: 0)
        #expect(titles.contains("狀態：舊資料夾／未連結"))
        #expect(titles.contains("開啟 Google Drive 管理…"))
        #expect(titles.contains("從側邊欄中移除"))
    }

    @Test("移除雲端位置只改顯示設定，不會刪除資料夾")
    func hidingCloudLocationIsReversible() {
        let directory = FileManager.default.temporaryDirectory
        let previous = UserDefaults.standard.object(
            forKey: HiddenCloudLocationStore.defaultsKey
        )
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: HiddenCloudLocationStore.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: HiddenCloudLocationStore.defaultsKey)
            }
        }

        HiddenCloudLocationStore.unhideAll()
        HiddenCloudLocationStore.hide(directory)

        #expect(HiddenCloudLocationStore.isHidden(directory))
        #expect(FileManager.default.fileExists(atPath: directory.path))

        HiddenCloudLocationStore.unhideAll()
        #expect(!HiddenCloudLocationStore.isHidden(directory))
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("路徑列右鍵提供拷貝資料夾及複製路徑")
    @MainActor
    func pathContextMenuTitles() {
        let controller = PaneViewController(
            storageKey: "ContextMenuPathTest",
            initialURL: FileManager.default.temporaryDirectory
        )
        _ = controller.view

        let titles = controller.pathContextMenuTitlesForTesting()
        #expect(titles.contains("複製路徑"))
        #expect(titles.contains { $0.hasPrefix("拷貝「") })
        #expect(titles.contains("取得資料"))
    }
    @Test("撳目前路徑會顯示完整路徑並可以複製")
    @MainActor
    func pathBarEditingShowsFullPath() {
        let directory = FileManager.default.temporaryDirectory.standardizedFileURL
        let parentDirectory = directory.deletingLastPathComponent().standardizedFileURL
        let controller = PaneViewController(
            storageKey: "PathBarEditingTest",
            initialURL: directory
        )
        _ = controller.view

        controller.beginPathEditingForTesting()
        #expect(controller.isPathEditingForTesting)
        #expect(controller.addressFieldTextForTesting == directory.path)


        controller.cancelPathEditingForTesting()
        #expect(!controller.isPathEditingForTesting)

        controller.beginPathEditingForTesting(url: parentDirectory)
        #expect(controller.isPathEditingForTesting)
        #expect(controller.addressFieldTextForTesting == parentDirectory.path)

        controller.cancelPathEditingForTesting()
        #expect(!controller.isPathEditingForTesting)
    }
    @Test("工具列顯示清楚嘅重新整理掣")
    @MainActor
    func refreshButtonIsVisible() {
        let controller = PaneViewController(
            storageKey: "RefreshButtonTest",
            initialURL: FileManager.default.temporaryDirectory
        )
        _ = controller.view

        #expect(controller.refreshButtonTitleForTesting == "重新整理")
        #expect(controller.refreshButtonIsVisibleForTesting)
    }

    @Test("右鍵新項目只揀該項，右鍵多選內項目會保留多選")
    @MainActor
    func contextClickSelectionSafety() {
        let controller = FileTableViewController()
        _ = controller.view
        let directory = FileManager.default.temporaryDirectory
        let items = ["A", "B", "C"].map { name in
            FileItem(
                url: directory.appendingPathComponent(name, isDirectory: true),
                isDirectory: true,
                isPackage: false,
                fileSize: nil,
                modifiedDate: nil,
                kind: "資料夾"
            )
        }
        controller.reload(items: items, currentDirectory: directory)

        controller.tableView.selectRowIndexes(
            IndexSet([0, 1]),
            byExtendingSelection: false
        )
        controller.selectListItemForContextMenu(at: 1)
        #expect(controller.tableView.selectedRowIndexes == IndexSet([0, 1]))

        controller.selectListItemForContextMenu(at: 2)
        #expect(controller.tableView.selectedRowIndexes == IndexSet(integer: 2))

        controller.selectListItemForContextMenu(at: -1)
        #expect(controller.tableView.selectedRowIndexes.isEmpty)
    }
}
