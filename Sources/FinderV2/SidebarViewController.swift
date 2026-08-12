import AppKit

private final class SidebarCellView: NSTableCellView {
    let ejectButton = NSButton()
}

protocol SidebarViewControllerDelegate: AnyObject {
    func sidebar(_ sidebar: SidebarViewController, didChoose location: SidebarLocation)
    func sidebar(
        _ sidebar: SidebarViewController,
        didReceive urls: [URL],
        at destination: URL,
        operation: FileTransferOperation
    )
}

final class SidebarViewController: NSViewController {
    weak var delegate: SidebarViewControllerDelegate?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let locationProvider: () -> [SidebarLocation]
    private let workspaceNotificationCenter: NotificationCenter
    private(set) var locations: [SidebarLocation] = []
    private var isUpdatingSelection = false
    private var isPreparingContextMenu = false
    private var contextFavoriteIndex: Int?
    private var contextLocationIndex: Int?

    init(
        locationProvider: @escaping () -> [SidebarLocation] = {
            SidebarLocationProvider.locations()
        },
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.locationProvider = locationProvider
        self.workspaceNotificationCenter = workspaceNotificationCenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        let heading = NSTextField(labelWithString: "常用位置")
        heading.font = .systemFont(ofSize: 10.5, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        heading.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(heading)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("location"))
        column.title = ""
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 27
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.registerForDraggedTypes([.fileURL])
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 11),
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 13),
            heading.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 5),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        self.view = root
        reloadLocations()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification
        ].forEach { name in
            workspaceNotificationCenter.addObserver(
                self,
                selector: #selector(mountedVolumesDidChange),
                name: name,
                object: nil
            )
        }
    }

    deinit {
        workspaceNotificationCenter.removeObserver(self)
    }

    func reloadLocations() {
        let selectedURL: URL?
        if tableView.selectedRow >= 0, tableView.selectedRow < locations.count {
            selectedURL = locations[tableView.selectedRow].url
        } else {
            selectedURL = nil
        }

        locations = locationProvider()
        tableView.reloadData()
        if let selectedURL {
            selectLocation(matching: selectedURL)
        }
    }

    func selectLocation(matching url: URL) {
        isUpdatingSelection = true
        defer { isUpdatingSelection = false }
        guard let index = locations.firstIndex(where: {
            $0.url.standardizedFileURL == url.standardizedFileURL
        }) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
    }

    private func dragOperation() -> FileTransferOperation {
        NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }

    @objc private func mountedVolumesDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            reloadLocations()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.reloadLocations()
            }
        }
    }

    private func draggedURLs(from draggingInfo: NSDraggingInfo) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        return (draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL]) ?? []
    }

    private func areFolders(_ urls: [URL]) -> Bool {
        !urls.isEmpty && urls.allSatisfy { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    @objc private func removeFavorite() {
        guard let index = contextFavoriteIndex,
              index >= 0,
              index < locations.count,
              locations[index].isFavorite else {
            return
        }
        FavoriteStore.shared.remove(locations[index].url)
        reloadLocations()
    }

    @objc private func editFavorite() {
        guard let index = contextFavoriteIndex,
              index >= 0,
              index < locations.count,
              let id = locations[index].favoriteID,
              let entry = FavoriteStore.shared.entries.first(where: { $0.id == id }) else {
            return
        }
        let titleField = NSTextField(string: entry.title)
        titleField.placeholderString = "顯示名稱"
        let groupField = NSTextField(string: entry.group)
        groupField.placeholderString = "分組，例如：工作"
        let stack = NSStackView(views: [titleField, groupField])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: 56)
        let alert = NSAlert()
        alert.messageText = "更改收藏"
        alert.informativeText = "可以改顯示名稱及分組："
        alert.accessoryView = stack
        alert.addButton(withTitle: "儲存")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        FavoriteStore.shared.update(
            id: id,
            title: title,
            group: groupField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        reloadLocations()
    }

    @objc private func moveFavoriteUp() {
        moveContextFavorite(offset: -1)
    }

    @objc private func moveFavoriteDown() {
        moveContextFavorite(offset: 1)
    }

    @objc private func ejectVolume(_ sender: NSButton) {
        ejectLocation(at: sender.tag)
    }

    @objc private func ejectContextVolume() {
        guard let index = contextLocationIndex else { return }
        ejectLocation(at: index)
    }

    @objc private func hideContextCloudLocation() {
        guard let location = contextLocation(), location.isCloudStorage else { return }
        HiddenCloudLocationStore.hide(location.url)
        reloadLocations()
    }

    @objc private func openCloudProviderManagement() {
        guard let location = contextLocation(),
              let bundleIdentifier = location.cloudProviderBundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
              ) else {
            showCloudManagementUnavailable()
            return
        }

        guard NSWorkspace.shared.open(appURL) else {
            showCloudManagementUnavailable()
            return
        }
    }

    @objc private func showHiddenCloudLocations() {
        HiddenCloudLocationStore.unhideAll()
        reloadLocations()
    }

    private func showCloudManagementUnavailable() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "搵唔到 Google Drive"
        alert.informativeText = "請先開啟或重新安裝 Google Drive，再管理帳戶連結。"
        alert.addButton(withTitle: "知道")
        alert.runModal()
    }

    func contextMenuTitlesForTesting(at row: Int) -> [String] {
        let menu = NSMenu()
        buildContextMenu(menu, for: row)
        return menu.items.map { item in
            item.isSeparatorItem ? "—" : item.title
        }
    }

    @objc private func openContextLocation() {
        guard let location = contextLocation() else { return }
        delegate?.sidebar(self, didChoose: location)
    }

    @objc private func copyContextLocation() {
        guard let location = contextLocation() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([location.url as NSURL])
    }

    @objc private func copyContextLocationPath() {
        guard let location = contextLocation() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(location.url.path, forType: .string)
    }

    @objc private func revealContextLocation() {
        guard let location = contextLocation() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([location.url])
    }

    @objc private func showContextLocationInfo() {
        guard let location = contextLocation() else { return }
        let values = try? location.url.resourceValues(forKeys: [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let size = values?.fileSize.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file)
        } ?? "—"
        let modified = values?.contentModificationDate.map {
            DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short)
        } ?? "—"
        let alert = NSAlert()
        alert.messageText = location.title
        alert.informativeText = [
            "種類：資料夾",
            "大小：\(size)",
            "修改日期：\(modified)",
            "位置：\(location.url.deletingLastPathComponent().path)"
        ].joined(separator: "\n")
        alert.addButton(withTitle: "知道")
        alert.runModal()
    }

    @objc private func addContextLocationToFavorites() {
        guard let location = contextLocation(), !location.isFavorite else { return }
        FavoriteStore.shared.add(location.url)
        reloadLocations()
    }

    private func prepareContextMenuSelection(at row: Int) {
        guard row >= 0,
              row < locations.count,
              !tableView.selectedRowIndexes.contains(row) else {
            return
        }
        isPreparingContextMenu = true
        defer { isPreparingContextMenu = false }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func contextLocation() -> SidebarLocation? {
        guard let index = contextLocationIndex,
              index >= 0,
              index < locations.count else {
            return nil
        }
        return locations[index]
    }

    private func moveContextFavorite(offset: Int) {
        guard let index = contextFavoriteIndex,
              index >= 0,
              index < locations.count,
              let id = locations[index].favoriteID else {
            return
        }
        let entries = FavoriteStore.shared.entries
        guard let current = entries.firstIndex(where: { $0.id == id }) else { return }
        FavoriteStore.shared.move(id: id, to: current + offset)
        reloadLocations()
    }

    private func ejectLocation(at index: Int) {
        guard index >= 0,
              index < locations.count,
              locations[index].isExternalVolume else {
            return
        }
        let location = locations[index]
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: location.url)
            reloadLocations()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "而家退出唔到"
            alert.informativeText = "可能仲有檔案用緊。請關閉相關檔案，再試一次。"
            alert.addButton(withTitle: "知道")
            alert.runModal()
        }
    }
}

extension SidebarViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        locations.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
        let cell: SidebarCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? SidebarCellView {
            cell = reused
        } else {
            cell = SidebarCellView()
            cell.identifier = identifier

            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyDown
            cell.imageView = icon
            cell.addSubview(icon)

            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            label.font = .systemFont(ofSize: 12.5)
            cell.textField = label
            cell.addSubview(label)

            cell.ejectButton.image = NSImage(
                systemSymbolName: "eject.fill",
                accessibilityDescription: "退出硬碟"
            )
            cell.ejectButton.imagePosition = .imageOnly
            cell.ejectButton.bezelStyle = .inline
            cell.ejectButton.isBordered = false
            cell.ejectButton.target = self
            cell.ejectButton.action = #selector(ejectVolume(_:))
            cell.ejectButton.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(cell.ejectButton)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 9),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),
                icon.heightAnchor.constraint(equalToConstant: 16),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.ejectButton.leadingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ,
                cell.ejectButton.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                cell.ejectButton.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                cell.ejectButton.widthAnchor.constraint(equalToConstant: 20),
                cell.ejectButton.heightAnchor.constraint(equalToConstant: 20)
            ])
        }

        let location = locations[row]
        cell.textField?.stringValue = location.title
        cell.imageView?.image = NSImage(
            systemSymbolName: location.symbolName,
            accessibilityDescription: location.title
        )
        cell.imageView?.contentTintColor = .controlAccentColor
        cell.ejectButton.tag = row
        cell.ejectButton.isHidden = !location.isExternalVolume
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection, !isPreparingContextMenu else { return }
        let row = tableView.selectedRow
        guard row >= 0, row < locations.count else { return }
        delegate?.sidebar(self, didChoose: locations[row])
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        let urls = draggedURLs(from: info)
        guard !urls.isEmpty else {
            return []
        }

        if areFolders(urls), row < 0 || row >= locations.count {
            tableView.setDropRow(locations.count, dropOperation: .above)
            return .link
        }

        guard row >= 0, row < locations.count else { return [] }
        tableView.setDropRow(row, dropOperation: .on)
        return dragOperation() == .copy ? .copy : .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        let urls = draggedURLs(from: info)
        guard !urls.isEmpty else { return false }

        if areFolders(urls), row < 0 || row >= locations.count {
            urls.forEach { FavoriteStore.shared.add($0) }
            reloadLocations()
            return true
        }

        guard row >= 0, row < locations.count else { return false }
        delegate?.sidebar(
            self,
            didReceive: urls,
            at: locations[row].url,
            operation: dragOperation()
        )
        return true
    }
}

extension SidebarViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        prepareContextMenuSelection(at: row)
        buildContextMenu(menu, for: row)
    }

    private func buildContextMenu(_ menu: NSMenu, for row: Int) {
        guard row >= 0, row < locations.count else {
            contextFavoriteIndex = nil
            contextLocationIndex = nil
            if HiddenCloudLocationStore.hasHiddenLocations {
                addContextMenuItem(
                    to: menu,
                    title: "顯示已隱藏雲端位置",
                    action: #selector(showHiddenCloudLocations)
                )
            }
            return
        }
        contextLocationIndex = row
        let location = locations[row]
        contextFavoriteIndex = location.isFavorite ? row : nil

        addContextMenuItem(
            to: menu,
            title: "開啟",
            action: #selector(openContextLocation)
        )
        addContextMenuItem(
            to: menu,
            title: "在 Apple Finder 顯示",
            action: #selector(revealContextLocation)
        )
        addContextMenuItem(
            to: menu,
            title: "拷貝「\(location.title)」",
            action: #selector(copyContextLocation)
        )
        addContextMenuItem(
            to: menu,
            title: "複製路徑",
            action: #selector(copyContextLocationPath)
        )
        menu.addItem(.separator())
        addContextMenuItem(
            to: menu,
            title: "取得資料",
            action: #selector(showContextLocationInfo)
        )

        if location.isCloudStorage {
            menu.addItem(.separator())
            let statusTitle = location.isFileProviderBacked
                ? "狀態：已連結"
                : "狀態：舊資料夾／未連結"
            let statusItem = menu.addItem(
                withTitle: statusTitle,
                action: nil,
                keyEquivalent: ""
            )
            statusItem.isEnabled = false
            if location.cloudProviderBundleIdentifier != nil {
                addContextMenuItem(
                    to: menu,
                    title: "開啟 Google Drive 管理…",
                    action: #selector(openCloudProviderManagement)
                )
            }
            addContextMenuItem(
                to: menu,
                title: "從側邊欄中移除",
                action: #selector(hideContextCloudLocation)
            )
        }
        if location.isFavorite {
            menu.addItem(.separator())
            addContextMenuItem(
                to: menu,
                title: "改名稱及分組…",
                action: #selector(editFavorite)
            )
            addContextMenuItem(
                to: menu,
                title: "向上移",
                action: #selector(moveFavoriteUp)
            )
            addContextMenuItem(
                to: menu,
                title: "向下移",
                action: #selector(moveFavoriteDown)
            )
            addContextMenuItem(
                to: menu,
                title: "移除收藏",
                action: #selector(removeFavorite)
            )
        } else {
            addContextMenuItem(
                to: menu,
                title: "加入收藏",
                action: #selector(addContextLocationToFavorites)
            )
        }

        if location.isExternalVolume {
            menu.addItem(.separator())
            addContextMenuItem(
                to: menu,
                title: "退出 \(location.title)",
                action: #selector(ejectContextVolume)
            )
        }
    }

    private func addContextMenuItem(
        to menu: NSMenu,
        title: String,
        action: Selector
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
    }
}
