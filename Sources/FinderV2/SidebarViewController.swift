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
    private(set) var locations: [SidebarLocation] = []
    private var isUpdatingSelection = false
    private var contextFavoriteIndex: Int?
    private var contextLocationIndex: Int?

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

    func reloadLocations() {
        locations = SidebarLocationProvider.locations()
        tableView.reloadData()
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
        guard !isUpdatingSelection else { return }
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
        guard row >= 0, row < locations.count else {
            contextFavoriteIndex = nil
            contextLocationIndex = nil
            return
        }
        contextLocationIndex = row

        if locations[row].isExternalVolume {
            contextFavoriteIndex = nil
            let eject = menu.addItem(
                withTitle: "退出 \(locations[row].title)",
                action: #selector(ejectContextVolume),
                keyEquivalent: ""
            )
            eject.target = self
            return
        }

        guard locations[row].isFavorite else {
            contextFavoriteIndex = nil
            return
        }

        contextFavoriteIndex = row
        let edit = menu.addItem(
            withTitle: "改名稱及分組…",
            action: #selector(editFavorite),
            keyEquivalent: ""
        )
        edit.target = self
        let up = menu.addItem(
            withTitle: "向上移",
            action: #selector(moveFavoriteUp),
            keyEquivalent: ""
        )
        up.target = self
        let down = menu.addItem(
            withTitle: "向下移",
            action: #selector(moveFavoriteDown),
            keyEquivalent: ""
        )
        down.target = self
        menu.addItem(.separator())
        let remove = menu.addItem(
            withTitle: "移除收藏",
            action: #selector(removeFavorite),
            keyEquivalent: ""
        )
        remove.target = self
    }
}
