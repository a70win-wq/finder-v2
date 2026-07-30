import AppKit

@main
enum FinderV2Application {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private var mainViewController: MainViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        let controller = MainViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1380, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Finder v2.0"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 980, height: 600)
        window.contentViewController = controller

        if let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        }

        let windowController = NSWindowController(window: window)
        self.windowController = windowController
        self.mainViewController = controller
        windowController.showWindow(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard OperationStatusCenter.shared.isBusy || TransferQueueCenter.shared.isBusy else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "檔案仲處理緊"
        alert.informativeText = "等完成先關閉，避免檔案搬到一半。"
        alert.addButton(withTitle: "繼續等")
        alert.addButton(withTitle: "唔關住")
        _ = alert.runModal()
        return .terminateCancel
    }

    @objc private func newFolder(_ sender: Any?) {
        mainViewController?.activePane?.createNewFolder()
    }

    @objc private func renameItem(_ sender: Any?) {
        mainViewController?.activePane?.renameSelectedItem()
    }

    @objc private func moveToTrash(_ sender: Any?) {
        mainViewController?.activePane?.moveSelectedItemsToTrash()
    }

    @objc private func refresh(_ sender: Any?) {
        mainViewController?.activePane?.reloadItems()
    }

    @objc private func openSelected(_ sender: Any?) {
        mainViewController?.activePane?.openSelectedItems()
    }

    @objc private func copyFiles(_ sender: Any?) {
        mainViewController?.activePane?.copySelectedItems()
    }

    @objc private func pasteFiles(_ sender: Any?) {
        mainViewController?.activePane?.pasteItems()
    }

    @objc private func duplicateFiles(_ sender: Any?) {
        mainViewController?.activePane?.duplicateSelectedItems()
    }

    @objc private func showInfo(_ sender: Any?) {
        mainViewController?.activePane?.showSelectedItemInfo()
    }

    @objc private func batchRename(_ sender: Any?) {
        mainViewController?.activePane?.batchRenameSelectedItems()
    }

    @objc private func createZip(_ sender: Any?) {
        mainViewController?.activePane?.createZipFromSelection()
    }

    @objc private func extractZip(_ sender: Any?) {
        mainViewController?.activePane?.extractSelectedZipFiles()
    }

    @objc private func compareFolders(_ sender: Any?) {
        mainViewController?.compareFolders()
    }

    @objc private func syncLeftToRight(_ sender: Any?) {
        mainViewController?.syncLeftToRight()
    }

    @objc private func syncRightToLeft(_ sender: Any?) {
        mainViewController?.syncRightToLeft()
    }

    @objc private func showTransferJobs(_ sender: Any?) {
        mainViewController?.showTransferJobs()
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "關於 Finder v2.0",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "離開 Finder v2.0",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "檔案")
        fileItem.submenu = fileMenu
        let openItem = fileMenu.addItem(
            withTitle: "開啟",
            action: #selector(openSelected(_:)),
            keyEquivalent: "o"
        )
        openItem.target = self
        let newFolderItem = fileMenu.addItem(
            withTitle: "新增資料夾",
            action: #selector(newFolder(_:)),
            keyEquivalent: "n"
        )
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        newFolderItem.target = self
        let renameItem = fileMenu.addItem(
            withTitle: "改名",
            action: #selector(renameItem(_:)),
            keyEquivalent: "\r"
        )
        renameItem.target = self
        let batchRenameItem = fileMenu.addItem(
            withTitle: "批量改名…",
            action: #selector(batchRename(_:)),
            keyEquivalent: ""
        )
        batchRenameItem.target = self
        let duplicateItem = fileMenu.addItem(
            withTitle: "製作副本",
            action: #selector(duplicateFiles(_:)),
            keyEquivalent: "d"
        )
        duplicateItem.target = self
        let infoItem = fileMenu.addItem(
            withTitle: "取得資料",
            action: #selector(showInfo(_:)),
            keyEquivalent: "i"
        )
        infoItem.target = self
        let zipItem = fileMenu.addItem(
            withTitle: "壓縮成 ZIP",
            action: #selector(createZip(_:)),
            keyEquivalent: ""
        )
        zipItem.target = self
        let extractItem = fileMenu.addItem(
            withTitle: "解壓 ZIP",
            action: #selector(extractZip(_:)),
            keyEquivalent: ""
        )
        extractItem.target = self
        fileMenu.addItem(.separator())
        let trashItem = fileMenu.addItem(
            withTitle: "搬去垃圾桶",
            action: #selector(moveToTrash(_:)),
            keyEquivalent: "\u{8}"
        )
        trashItem.keyEquivalentModifierMask = [.command]
        trashItem.target = self

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "編輯")
        editItem.submenu = editMenu
        let copyItem = editMenu.addItem(
            withTitle: "複製",
            action: #selector(copyFiles(_:)),
            keyEquivalent: "c"
        )
        copyItem.target = self
        let pasteItem = editMenu.addItem(
            withTitle: "貼上",
            action: #selector(pasteFiles(_:)),
            keyEquivalent: "v"
        )
        pasteItem.target = self
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "還原",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redoItem = editMenu.addItem(
            withTitle: "重做",
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "全選",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "顯示方式")
        viewItem.submenu = viewMenu
        let refreshItem = viewMenu.addItem(
            withTitle: "重新整理",
            action: #selector(refresh(_:)),
            keyEquivalent: "r"
        )
        refreshItem.target = self

        let toolsItem = NSMenuItem()
        mainMenu.addItem(toolsItem)
        let toolsMenu = NSMenu(title: "工具")
        toolsItem.submenu = toolsMenu
        let compareItem = toolsMenu.addItem(
            withTitle: "比較左右",
            action: #selector(compareFolders(_:)),
            keyEquivalent: ""
        )
        compareItem.target = self
        let syncRightItem = toolsMenu.addItem(
            withTitle: "同步左邊到右邊",
            action: #selector(syncLeftToRight(_:)),
            keyEquivalent: ""
        )
        syncRightItem.target = self
        let syncLeftItem = toolsMenu.addItem(
            withTitle: "同步右邊到左邊",
            action: #selector(syncRightToLeft(_:)),
            keyEquivalent: ""
        )
        syncLeftItem.target = self
        toolsMenu.addItem(.separator())
        let jobsItem = toolsMenu.addItem(
            withTitle: "搬檔工作清單",
            action: #selector(showTransferJobs(_:)),
            keyEquivalent: ""
        )
        jobsItem.target = self

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "視窗")
        windowItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: "縮到最小",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "放大",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        NSApplication.shared.windowsMenu = windowMenu

        NSApplication.shared.mainMenu = mainMenu
    }
}
