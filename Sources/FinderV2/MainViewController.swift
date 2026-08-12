import AppKit

final class MainSplitView: NSSplitView {
    var onWillResize: (() -> Void)?
    var onDidResize: (() -> Void)?

    override var dividerThickness: CGFloat { 7 }

    override func mouseDown(with event: NSEvent) {
        onWillResize?()
        super.mouseDown(with: event)
        onDidResize?()
    }

    override func drawDivider(in rect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        rect.fill()

        let lineRect: NSRect
        if isVertical {
            lineRect = NSRect(
                x: rect.midX - 0.5,
                y: rect.minY,
                width: 1,
                height: rect.height
            )
        } else {
            lineRect = NSRect(
                x: rect.minX,
                y: rect.midY - 0.5,
                width: rect.width,
                height: 1
            )
        }
        NSColor.separatorColor.setFill()
        lineRect.fill()
    }
}

enum PaneLayout: Int, CaseIterable {
    case sideBySide
    case stacked
    case threeLeft
    case threeRight
    case threeTop
    case threeBottom
    case fourGrid
    case fourColumns
    case fourRows

    var title: String {
        switch self {
        case .sideBySide: return "左右雙開"
        case .stacked: return "上下雙開"
        case .threeLeft: return "三開：左一右二"
        case .threeRight: return "三開：左二右一"
        case .threeTop: return "三開：上一下二"
        case .threeBottom: return "三開：上二下一"
        case .fourGrid: return "四開：四格"
        case .fourColumns: return "四開：左右四欄"
        case .fourRows: return "四開：上下四列"
        }
    }

    var symbolName: String {
        switch self {
        case .sideBySide: return "rectangle.split.2x1"
        case .stacked: return "rectangle.split.1x2"
        case .threeLeft: return "rectangle.split.3x1"
        case .threeRight: return "rectangle.split.3x1"
        case .threeTop: return "rectangle.split.1x2"
        case .threeBottom: return "rectangle.split.1x2"
        case .fourGrid: return "square.grid.2x2"
        case .fourColumns: return "rectangle.split.3x1"
        case .fourRows: return "rectangle.grid.1x2"
        }
    }

    var paneCount: Int {
        switch self {
        case .sideBySide, .stacked: return 2
        case .threeLeft, .threeRight, .threeTop, .threeBottom: return 3
        case .fourGrid, .fourColumns, .fourRows: return 4
        }
    }
}

final class MainViewController: NSViewController {
    static let layoutDefaultsKey = "FinderV2PaneLayout"

    private(set) var leftPane: PaneViewController!
    private(set) var rightPane: PaneViewController!
    private(set) var activePane: PaneViewController?
    private(set) var mainSplitView: MainSplitView!

    private var panes: [PaneViewController] = []
    private var visiblePanes: [PaneViewController] = []
    private var layoutController: NSSplitViewController?
    private var needsInitialPaneEqualization = false
    private var lockedLayoutConstraints: [ObjectIdentifier: [NSLayoutConstraint]] = [:]
    private(set) var currentLayout: PaneLayout = .sideBySide
    private let layoutContainer = NSView()
    private let layoutPopUp = NSPopUpButton()
    private let comparisonLabel = NSTextField(labelWithString: "")

    var visiblePaneCount: Int { visiblePanes.count }

    override func viewDidLayout() {
        super.viewDidLayout()
        equalizeInitialPanesIfNeeded()
    }

    override func loadView() {
        configurePanes()

        let root = NSView()
        let toolsBar = NSVisualEffectView()
        toolsBar.material = .titlebar
        toolsBar.blendingMode = .behindWindow
        toolsBar.state = .active
        toolsBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolsBar)

        configureLayoutPopUp()

        let compareButton = NSButton(title: "比較 1／2", target: self, action: #selector(compareFolders))
        styleToolbarButton(compareButton, symbol: "rectangle.split.2x1", tooltip: "比較第 1 格同第 2 格")
        let syncRightButton = NSButton(title: "1 → 2", target: self, action: #selector(syncLeftToRight))
        styleToolbarButton(syncRightButton, symbol: "arrow.right.circle", tooltip: "同步第 1 格到第 2 格")
        let syncLeftButton = NSButton(title: "2 → 1", target: self, action: #selector(syncRightToLeft))
        styleToolbarButton(syncLeftButton, symbol: "arrow.left.circle", tooltip: "同步第 2 格到第 1 格")
        let jobsButton = NSButton(title: "工作清單", target: self, action: #selector(showTransferJobs))
        styleToolbarButton(jobsButton, symbol: "list.bullet.rectangle", tooltip: "搬檔工作清單")

        let tools = NSStackView(
            views: [
                layoutPopUp,
                makeSeparator(),
                compareButton,
                makeSeparator(),
                syncRightButton,
                syncLeftButton,
                makeSeparator(),
                jobsButton
            ]
        )
        tools.orientation = .horizontal
        tools.alignment = .centerY
        tools.spacing = 6
        tools.translatesAutoresizingMaskIntoConstraints = false
        toolsBar.addSubview(tools)

        comparisonLabel.textColor = .secondaryLabelColor
        comparisonLabel.font = .systemFont(ofSize: 11.5)
        comparisonLabel.lineBreakMode = .byTruncatingTail
        comparisonLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        comparisonLabel.translatesAutoresizingMaskIntoConstraints = false
        toolsBar.addSubview(comparisonLabel)

        layoutContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(layoutContainer)
        NSLayoutConstraint.activate([
            toolsBar.topAnchor.constraint(equalTo: root.topAnchor),
            toolsBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolsBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolsBar.heightAnchor.constraint(equalToConstant: 53),

            tools.leadingAnchor.constraint(equalTo: toolsBar.leadingAnchor, constant: 82),
            tools.centerYAnchor.constraint(equalTo: toolsBar.centerYAnchor, constant: 5),

            comparisonLabel.leadingAnchor.constraint(equalTo: tools.trailingAnchor, constant: 12),
            comparisonLabel.trailingAnchor.constraint(equalTo: toolsBar.trailingAnchor, constant: -10),
            comparisonLabel.centerYAnchor.constraint(equalTo: toolsBar.centerYAnchor, constant: 5),

            layoutContainer.topAnchor.constraint(equalTo: toolsBar.bottomAnchor),
            layoutContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            layoutContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            layoutContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        self.view = root

        let savedRawValue = UserDefaults.standard.integer(forKey: Self.layoutDefaultsKey)
        currentLayout = PaneLayout(rawValue: savedRawValue) ?? .sideBySide
        layoutPopUp.selectItem(at: currentLayout.rawValue)
        applyLayout(currentLayout)
    }

    @objc func compareFolders() {
        let result = FolderComparisonEngine.compare(
            left: leftPane.currentItems,
            right: rightPane.currentItems
        )
        leftPane.showComparison(result.left)
        rightPane.showComparison(result.right)
        comparisonLabel.stringValue = "藍色：只在一邊 · 橙色：版本唔同 · 灰色：一樣"

        let alert = NSAlert()
        alert.messageText = "比較完成"
        alert.informativeText = """
        第 1 格獨有：\(result.leftOnlyCount) 個
        第 2 格獨有：\(result.rightOnlyCount) 個
        版本唔同：\(result.differentCount) 個
        完全一樣：\(result.sameCount) 個
        """
        alert.addButton(withTitle: "知道")
        alert.addButton(withTitle: "清除顏色")
        if alert.runModal() == .alertSecondButtonReturn {
            leftPane.clearComparison()
            rightPane.clearComparison()
            comparisonLabel.stringValue = ""
        }
    }

    @objc func syncLeftToRight() {
        offerSync(from: leftPane, to: rightPane, direction: "第 1 格 → 第 2 格")
    }

    @objc func syncRightToLeft() {
        offerSync(from: rightPane, to: leftPane, direction: "第 2 格 → 第 1 格")
    }

    @objc func showTransferJobs() {
        TransferQueueWindowController.shared.show()
    }

    private func offerSync(
        from sourcePane: PaneViewController,
        to destinationPane: PaneViewController,
        direction: String
    ) {
        guard sourcePane.currentDirectory.standardizedFileURL
            != destinationPane.currentDirectory.standardizedFileURL else {
            showMessage(title: "兩邊係同一個資料夾", message: "唔需要同步。")
            return
        }
        let sources = FolderComparisonEngine.syncSources(
            from: sourcePane.currentItems,
            to: destinationPane.currentItems
        )
        guard !sources.isEmpty else {
            showMessage(title: "已經一樣", message: "冇檔案需要同步。")
            return
        }
        let sample = sources.prefix(8).map(\.lastPathComponent).joined(separator: "\n")
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "同步 \(direction)？"
        alert.informativeText = """
        會複製 \(sources.count) 個較新或右邊未有嘅項目。
        同名舊版本會放入垃圾桶後取代。

        \(sample)\(sources.count > 8 ? "\n…" : "")
        """
        alert.addButton(withTitle: "開始同步")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        sourcePane.copyForSync(sources, to: destinationPane.currentDirectory) { [weak self] in
            self?.comparisonLabel.stringValue = "同步完成；可以再按「比較左右」查看最新結果"
        }
        showTransferJobs()
    }

    private func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "知道")
        alert.runModal()
    }

    private func activate(_ pane: PaneViewController) {
        activePane = pane
        panes.forEach { $0.setActive($0 === pane) }
    }

    @objc private func layoutChanged() {
        guard let layout = PaneLayout(rawValue: layoutPopUp.indexOfSelectedItem) else { return }
        UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutDefaultsKey)
        applyLayout(layout)
    }

    private func configurePanes() {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let configurations: [(key: String, fallback: URL)] = [
            ("FinderV2LeftFolder", home.appendingPathComponent("Downloads", isDirectory: true)),
            ("FinderV2RightFolder", home.appendingPathComponent("Documents", isDirectory: true)),
            ("FinderV2Pane3Folder", home.appendingPathComponent("Desktop", isDirectory: true)),
            ("FinderV2Pane4Folder", home)
        ]
        panes = configurations.map { configuration in
            PaneViewController(
                storageKey: configuration.key,
                initialURL: restoredURL(forKey: configuration.key, fallback: configuration.fallback)
            )
        }
        leftPane = panes[0]
        rightPane = panes[1]
        panes.forEach { pane in
            pane.didActivate = { [weak self] activatedPane in
                self?.activate(activatedPane)
            }
        }
    }

    private func configureLayoutPopUp() {
        layoutPopUp.removeAllItems()
        PaneLayout.allCases.forEach { layout in
            layoutPopUp.addItem(withTitle: layout.title)
            layoutPopUp.lastItem?.image = NSImage(
                systemSymbolName: layout.symbolName,
                accessibilityDescription: layout.title
            )
        }
        layoutPopUp.target = self
        layoutPopUp.action = #selector(layoutChanged)
        layoutPopUp.toolTip = "選擇雙開、三開或四開版面"
        layoutPopUp.bezelStyle = .accessoryBarAction
        layoutPopUp.controlSize = .regular
        layoutPopUp.font = .systemFont(ofSize: 12, weight: .medium)
        layoutPopUp.imagePosition = .imageLeading
        layoutPopUp.translatesAutoresizingMaskIntoConstraints = false
        layoutPopUp.widthAnchor.constraint(equalToConstant: 170).isActive = true
        layoutPopUp.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    func applyLayout(_ layout: PaneLayout) {
        lockedLayoutConstraints.values.forEach(NSLayoutConstraint.deactivate)
        lockedLayoutConstraints.removeAll()
        currentLayout = layout
        comparisonLabel.stringValue = ""
        panes.forEach { $0.clearComparison() }

        panes.forEach { pane in
            pane.view.removeFromSuperview()
            pane.removeFromParent()
        }
        layoutController?.view.removeFromSuperview()
        layoutController?.removeFromParent()

        let controller: NSSplitViewController
        switch layout {
        case .sideBySide:
            controller = makeSplit(
                isVertical: true,
                controllers: [panes[0], panes[1]],
                minimumThickness: 300
            )
        case .stacked:
            controller = makeSplit(
                isVertical: false,
                controllers: [panes[0], panes[1]],
                minimumThickness: 220
            )
        case .threeLeft:
            let rightStack = makeSplit(
                isVertical: false,
                controllers: [panes[1], panes[2]],
                minimumThickness: 210
            )
            controller = makeSplit(
                isVertical: true,
                controllers: [panes[0], rightStack],
                minimumThickness: 300
            )
        case .threeRight:
            let leftStack = makeSplit(
                isVertical: false,
                controllers: [panes[0], panes[1]],
                minimumThickness: 210
            )
            controller = makeSplit(
                isVertical: true,
                controllers: [leftStack, panes[2]],
                minimumThickness: 300
            )
        case .threeTop:
            let bottomRow = makeSplit(
                isVertical: true,
                controllers: [panes[1], panes[2]],
                minimumThickness: 280
            )
            controller = makeSplit(
                isVertical: false,
                controllers: [panes[0], bottomRow],
                minimumThickness: 210
            )
        case .threeBottom:
            let topRow = makeSplit(
                isVertical: true,
                controllers: [panes[0], panes[1]],
                minimumThickness: 280
            )
            controller = makeSplit(
                isVertical: false,
                controllers: [topRow, panes[2]],
                minimumThickness: 210
            )
        case .fourGrid:
            let topRow = makeSplit(
                isVertical: true,
                controllers: [panes[0], panes[1]],
                minimumThickness: 280
            )
            let bottomRow = makeSplit(
                isVertical: true,
                controllers: [panes[2], panes[3]],
                minimumThickness: 280
            )
            controller = makeSplit(
                isVertical: false,
                controllers: [topRow, bottomRow],
                minimumThickness: 195
            )
        case .fourColumns:
            controller = makeSplit(
                isVertical: true,
                controllers: panes,
                minimumThickness: 220
            )
        case .fourRows:
            controller = makeSplit(
                isVertical: false,
                controllers: panes,
                minimumThickness: 120
            )
        }

        layoutController = controller
        mainSplitView = controller.splitView as? MainSplitView
        visiblePanes = Array(panes.prefix(layout.paneCount))
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        layoutContainer.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: layoutContainer.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: layoutContainer.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: layoutContainer.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: layoutContainer.bottomAnchor)
        ])
        lockEqualSplitRatiosRecursively(controller)
        activate(visiblePanes[0])

        layoutContainer.needsLayout = true
        layoutContainer.layoutSubtreeIfNeeded()
        needsInitialPaneEqualization = true
        equalizeInitialPanesIfNeeded()
        view.needsLayout = true
    }

    private func makeSplit(
        isVertical: Bool,
        controllers: [NSViewController],
        minimumThickness: CGFloat
    ) -> NSSplitViewController {
        let splitController = NSSplitViewController()
        let splitView = MainSplitView()
        splitView.isVertical = isVertical
        splitView.dividerStyle = .thick
        splitController.splitView = splitView
        let preferredFraction = 1 / CGFloat(controllers.count)
        controllers.forEach { childController in
            let item = NSSplitViewItem(viewController: childController)
            item.minimumThickness = minimumThickness
            item.preferredThicknessFraction = preferredFraction
            item.holdingPriority = .defaultLow
            item.canCollapse = false
            splitController.addSplitViewItem(item)
        }
        return splitController
    }

    private func equalizeInitialPanesIfNeeded() {
        guard needsInitialPaneEqualization,
              layoutContainer.bounds.width > 0,
              layoutContainer.bounds.height > 0,
              let layoutController else {
            return
        }

        needsInitialPaneEqualization = false
        equalizeRecursively(layoutController)
    }

    private func lockEqualSplitRatiosRecursively(
        _ controller: NSSplitViewController
    ) {
        lockSplitRatios(controller.splitView, ratios: nil)
        controller.splitViewItems.forEach { splitViewItem in
            guard let nestedController = splitViewItem.viewController as? NSSplitViewController else {
                return
            }
            lockEqualSplitRatiosRecursively(nestedController)
        }
    }

    private func lockCurrentSplitRatio(_ splitView: NSSplitView) {
        guard let firstView = splitView.arrangedSubviews.first else { return }
        let firstThickness = splitView.isVertical
            ? firstView.frame.width
            : firstView.frame.height
        guard firstThickness > 0 else { return }
        let ratios = splitView.arrangedSubviews.dropFirst().map { siblingView in
            let siblingThickness = splitView.isVertical
                ? siblingView.frame.width
                : siblingView.frame.height
            return firstThickness / max(1, siblingThickness)
        }
        lockSplitRatios(splitView, ratios: ratios)
    }

    private func lockSplitRatios(
        _ splitView: NSSplitView,
        ratios: [CGFloat]?
    ) {
        guard let firstView = splitView.arrangedSubviews.first else { return }
        let identifier = ObjectIdentifier(splitView)
        if let oldConstraints = lockedLayoutConstraints.removeValue(forKey: identifier) {
            NSLayoutConstraint.deactivate(oldConstraints)
        }

        let constraints = splitView.arrangedSubviews.dropFirst().enumerated().map {
            offset,
            siblingView -> NSLayoutConstraint in
            let multiplier = ratios.flatMap {
                offset < $0.count ? $0[offset] : nil
            } ?? 1
            let constraint: NSLayoutConstraint
            if splitView.isVertical {
                constraint = firstView.widthAnchor.constraint(
                    equalTo: siblingView.widthAnchor,
                    multiplier: multiplier
                )
            } else {
                constraint = firstView.heightAnchor.constraint(
                    equalTo: siblingView.heightAnchor,
                    multiplier: multiplier
                )
            }
            constraint.priority = .init(999)
            return constraint
        }
        NSLayoutConstraint.activate(constraints)
        lockedLayoutConstraints[identifier] = constraints

        guard let mainSplitView = splitView as? MainSplitView else { return }
        mainSplitView.onWillResize = { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            let identifier = ObjectIdentifier(splitView)
            guard let constraints = lockedLayoutConstraints.removeValue(
                forKey: identifier
            ) else {
                return
            }
            NSLayoutConstraint.deactivate(constraints)
        }
        mainSplitView.onDidResize = { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            lockCurrentSplitRatio(splitView)
        }
    }

    private func equalizeRecursively(_ controller: NSSplitViewController) {
        let splitView = controller.splitView
        splitView.layoutSubtreeIfNeeded()

        controller.splitViewItems.forEach { splitViewItem in
            guard let nestedController = splitViewItem.viewController as? NSSplitViewController else {
                return
            }
            equalizeRecursively(nestedController)
        }

        splitView.layoutSubtreeIfNeeded()
        let paneCount = splitView.arrangedSubviews.count
        if paneCount > 1 {
            let axisLength = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            let totalDividerThickness = splitView.dividerThickness * CGFloat(paneCount - 1)
            let availablePaneThickness = axisLength - totalDividerThickness

            if availablePaneThickness > 0 {
                for dividerIndex in 0..<(paneCount - 1) {
                    let precedingPaneCount = CGFloat(dividerIndex + 1)
                    let dividerPosition =
                        availablePaneThickness * precedingPaneCount / CGFloat(paneCount)
                        + splitView.dividerThickness * CGFloat(dividerIndex)
                    splitView.setPosition(dividerPosition, ofDividerAt: dividerIndex)
                }
            }
        }
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 22).isActive = true
        separator.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func styleToolbarButton(_ button: NSButton, symbol: String, tooltip: String) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.alignment = .center
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .regular
        button.contentTintColor = .labelColor
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    private func restoredURL(forKey key: String, fallback: URL) -> URL {
        guard let path = UserDefaults.standard.string(forKey: key) else {
            return fallback
        }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return fallback
        }
        return url
    }
}
