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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageChanged),
            name: .finderV2LanguageChanged,
            object: nil
        )
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
        alert.messageText = L("檔案仲處理緊")
        alert.informativeText = L("等完成先關閉，避免檔案搬到一半。")
        alert.addButton(withTitle: L("繼續等"))
        alert.addButton(withTitle: L("唔關住"))
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
        guard !firstResponderIsEditingText else { return }
        mainViewController?.activePane?.moveSelectedItemsToTrash()
    }

    @objc private func refresh(_ sender: Any?) {
        mainViewController?.activePane?.reloadItems()
    }

    @objc private func openSelected(_ sender: Any?) {
        mainViewController?.activePane?.openSelectedItems()
    }

    @objc private func copyFiles(_ sender: Any?) {
        if firstResponderIsEditingText {
            NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: sender)
            return
        }
        mainViewController?.activePane?.copySelectedItems()
    }

    @objc private func pasteFiles(_ sender: Any?) {
        if firstResponderIsEditingText {
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: sender)
            return
        }
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

    private var firstResponderIsEditingText: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return responder is NSText || responder is NSTextView || responder is NSTextField
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appItem.submenu = appMenu
        appMenu.addItem(
            withTitle: L("關於 Finder v2.0"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        let languageItem = NSMenuItem(title: L("語言"), action: nil, keyEquivalent: "")
        languageItem.submenu = makeLanguageMenu()
        appMenu.addItem(languageItem)
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: L("離開 Finder v2.0"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: L("檔案"))
        fileItem.submenu = fileMenu
        let openItem = fileMenu.addItem(
            withTitle: L("開啟"),
            action: #selector(openSelected(_:)),
            keyEquivalent: "o"
        )
        openItem.target = self
        let newFolderItem = fileMenu.addItem(
            withTitle: L("新增資料夾"),
            action: #selector(newFolder(_:)),
            keyEquivalent: "n"
        )
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        newFolderItem.target = self
        let renameItem = fileMenu.addItem(
            withTitle: L("改名"),
            action: #selector(renameItem(_:)),
            keyEquivalent: "\r"
        )
        renameItem.target = self
        let batchRenameItem = fileMenu.addItem(
            withTitle: L("批量改名…"),
            action: #selector(batchRename(_:)),
            keyEquivalent: ""
        )
        batchRenameItem.target = self
        let duplicateItem = fileMenu.addItem(
            withTitle: L("製作副本"),
            action: #selector(duplicateFiles(_:)),
            keyEquivalent: "d"
        )
        duplicateItem.target = self
        let infoItem = fileMenu.addItem(
            withTitle: L("取得資料"),
            action: #selector(showInfo(_:)),
            keyEquivalent: "i"
        )
        infoItem.target = self
        let zipItem = fileMenu.addItem(
            withTitle: L("壓縮成 ZIP"),
            action: #selector(createZip(_:)),
            keyEquivalent: ""
        )
        zipItem.target = self
        let extractItem = fileMenu.addItem(
            withTitle: L("解壓 ZIP"),
            action: #selector(extractZip(_:)),
            keyEquivalent: ""
        )
        extractItem.target = self
        fileMenu.addItem(.separator())
        let trashItem = fileMenu.addItem(
            withTitle: L("搬去垃圾桶"),
            action: #selector(moveToTrash(_:)),
            keyEquivalent: "\u{8}"
        )
        trashItem.keyEquivalentModifierMask = [.command]
        trashItem.target = self

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: L("編輯"))
        editItem.submenu = editMenu
        let copyItem = editMenu.addItem(
            withTitle: L("複製"),
            action: #selector(copyFiles(_:)),
            keyEquivalent: "c"
        )
        copyItem.target = self
        let pasteItem = editMenu.addItem(
            withTitle: L("貼上"),
            action: #selector(pasteFiles(_:)),
            keyEquivalent: "v"
        )
        pasteItem.target = self
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: L("還原"),
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redoItem = editMenu.addItem(
            withTitle: L("重做"),
            action: Selector(("redo:")),
            keyEquivalent: "Z"
        )
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: L("全選"),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: L("顯示方式"))
        viewItem.submenu = viewMenu
        let refreshItem = viewMenu.addItem(
            withTitle: L("重新整理"),
            action: #selector(refresh(_:)),
            keyEquivalent: "r"
        )
        refreshItem.target = self

        let toolsItem = NSMenuItem()
        mainMenu.addItem(toolsItem)
        let toolsMenu = NSMenu(title: L("工具"))
        toolsItem.submenu = toolsMenu
        let compareItem = toolsMenu.addItem(
            withTitle: L("比較左右"),
            action: #selector(compareFolders(_:)),
            keyEquivalent: ""
        )
        compareItem.target = self
        let syncRightItem = toolsMenu.addItem(
            withTitle: L("同步左邊到右邊"),
            action: #selector(syncLeftToRight(_:)),
            keyEquivalent: ""
        )
        syncRightItem.target = self
        let syncLeftItem = toolsMenu.addItem(
            withTitle: L("同步右邊到左邊"),
            action: #selector(syncRightToLeft(_:)),
            keyEquivalent: ""
        )
        syncLeftItem.target = self
        toolsMenu.addItem(.separator())
        let jobsItem = toolsMenu.addItem(
            withTitle: L("搬檔工作清單"),
            action: #selector(showTransferJobs(_:)),
            keyEquivalent: ""
        )
        jobsItem.target = self

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: L("視窗"))
        windowItem.submenu = windowMenu
        windowMenu.addItem(
            withTitle: L("縮到最小"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: L("放大"),
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        NSApplication.shared.windowsMenu = windowMenu

        NSApplication.shared.mainMenu = mainMenu
    }

    private func makeLanguageMenu() -> NSMenu {
        let menu = NSMenu(title: L("語言"))
        let systemItem = menu.addItem(
            withTitle: L("跟隨系統"),
            action: #selector(followSystemLanguage(_:)),
            keyEquivalent: ""
        )
        systemItem.target = self
        systemItem.state = Localization.followsSystemLanguage ? .on : .off
        menu.addItem(.separator())
        for language in Localization.supportedLanguages {
            let item = menu.addItem(
                withTitle: Localization.nativeName(for: language),
                action: #selector(selectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = language
            item.state = !Localization.followsSystemLanguage
                && Localization.preferredLanguage == language
                ? .on
                : .off
        }
        return menu
    }

    @objc private func languageChanged() {
        buildMainMenu()
    }

    @objc private func followSystemLanguage(_ sender: Any?) {
        Localization.followSystemLanguage()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? String else { return }
        Localization.preferredLanguage = language
    }
}
