import AppKit
import Quartz
import UniformTypeIdentifiers

private final class FinderPathControl: NSPathControl {
    var makeContextMenu: ((URL) -> NSMenu?)?
    var onPrimaryClick: ((URL?) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let componentURL = (cell as? NSPathCell)?
            .pathComponentCell(at: point, withFrame: bounds, in: self)?
            .url
        onPrimaryClick?(componentURL)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let pathCell = cell as? NSPathCell,
              let component = pathCell.pathComponentCell(
                  at: point,
                  withFrame: bounds,
                  in: self
              ),
              let url = component.url else {
            return nil
        }
        return makeContextMenu?(url)
    }
}

private final class FinderAddressField: NSTextField {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

final class PaneViewController: NSViewController {
    let storageKey: String
    var didActivate: ((PaneViewController) -> Void)?

    private let initialURL: URL
    private let sidebarController = SidebarViewController()
    private let fileTableController = FileTableViewController()
    private let pathControl = FinderPathControl()
    private let addressField = FinderAddressField()
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let upButton = NSButton()
    private let viewModeControl = NSSegmentedControl()
    private let searchField = NSSearchField()
    private let refreshButton = NSButton()
    private let sortPopUp = NSPopUpButton()
    private let sortDirectionButton = NSButton()
    private let hiddenFilesButton = NSButton()
    private let favoriteButton = NSButton()
    private let chooseFolderButton = NSButton()
    private let newFolderButton = NSButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let cancelOperationButton = NSButton(title: L("取消"), target: nil, action: nil)
    private let contentSplitView = NSSplitView()
    private let directoryMonitor = DirectoryMonitor()

    private var history: [URL] = []
    private var historyIndex = -1
    private var reloadRequestID = 0
    private var allItems: [FileItem] = []
    private(set) var sortOption: FileSortOption = .name
    private(set) var sortAscending = true
    private(set) var showHiddenFiles = false
    private var quickLookURLs: [URL] = []
    private(set) var currentDirectory: URL
    private var isEditingPath = false
    private var isMonitoringEnabled = true
    var currentItems: [FileItem] { allItems }

    init(storageKey: String, initialURL: URL) {
        self.storageKey = storageKey
        self.initialURL = initialURL
        self.currentDirectory = initialURL
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

        let toolbar = NSVisualEffectView()
        toolbar.material = .contentBackground
        toolbar.blendingMode = .behindWindow
        toolbar.state = .active
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(toolbar)

        configureButton(backButton, symbol: "chevron.left", tooltip: L("返回"), action: #selector(goBack))
        configureButton(forwardButton, symbol: "chevron.right", tooltip: L("前進"), action: #selector(goForward))
        configureButton(upButton, symbol: "arrow.up", tooltip: L("上一層"), action: #selector(goUp))
        configureButton(refreshButton, symbol: "arrow.clockwise", tooltip: L("重新整理"), action: #selector(refreshPressed), title: L("重新整理"), width: 78)
        configureButton(chooseFolderButton, symbol: "folder", tooltip: L("選擇資料夾"), action: #selector(chooseFolderPressed))
        configureButton(newFolderButton, symbol: "folder.badge.plus", tooltip: L("新增資料夾"), action: #selector(newFolderPressed))

        viewModeControl.segmentCount = 4
        viewModeControl.trackingMode = .selectOne
        viewModeControl.segmentStyle = .rounded
        viewModeControl.controlSize = .regular
        viewModeControl.setImage(
            NSImage(systemSymbolName: "list.bullet", accessibilityDescription: L("清單")),
            forSegment: FileViewMode.list.rawValue
        )
        viewModeControl.setImage(
            NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: L("大圖示")),
            forSegment: FileViewMode.icons.rawValue
        )
        viewModeControl.setImage(
            NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: L("直欄")),
            forSegment: FileViewMode.columns.rawValue
        )
        viewModeControl.setImage(
            NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: L("圖庫")),
            forSegment: FileViewMode.gallery.rawValue
        )
        viewModeControl.setToolTip(L("清單"), forSegment: FileViewMode.list.rawValue)
        viewModeControl.setToolTip(L("大圖示"), forSegment: FileViewMode.icons.rawValue)
        viewModeControl.setToolTip(L("直欄"), forSegment: FileViewMode.columns.rawValue)
        viewModeControl.setToolTip(L("圖庫"), forSegment: FileViewMode.gallery.rawValue)
        viewModeControl.setAccessibilityLabel(L("顯示方式"))
        viewModeControl.target = self
        viewModeControl.action = #selector(viewModeChanged)
        viewModeControl.translatesAutoresizingMaskIntoConstraints = false
        viewModeControl.widthAnchor.constraint(equalToConstant: 112).isActive = true
        viewModeControl.heightAnchor.constraint(equalToConstant: 28).isActive = true

        let navigationStack = NSStackView(views: [backButton, forwardButton, upButton])
        navigationStack.orientation = .horizontal
        navigationStack.spacing = 3
        navigationStack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(navigationStack)

        pathControl.pathStyle = .standard
        pathControl.controlSize = .regular
        pathControl.font = .systemFont(ofSize: 12, weight: .medium)
        pathControl.target = self
        pathControl.action = #selector(pathControlClicked)
        pathControl.makeContextMenu = { [weak self] url in
            self?.makePathContextMenu(for: url)
        }
        pathControl.onPrimaryClick = { [weak self] url in
            self?.showPath(for: url)
        }
        pathControl.setContentCompressionResistancePriority(
            NSLayoutConstraint.Priority(1),
            for: .horizontal
        )
        pathControl.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(pathControl)

        addressField.controlSize = .regular
        addressField.font = .systemFont(ofSize: 12)
        addressField.isEditable = true
        addressField.isSelectable = true
        addressField.usesSingleLineMode = true
        addressField.lineBreakMode = .byTruncatingMiddle
        addressField.placeholderString = L("完整路徑")
        addressField.toolTip = L("按 Command-C 複製完整路徑；Return 開啟；Escape 返回")
        addressField.setAccessibilityLabel(L("完整路徑"))
        addressField.target = self
        addressField.action = #selector(pathEditingCommitted)
        addressField.onCancel = { [weak self] in self?.endPathEditing() }
        addressField.isHidden = true
        addressField.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(addressField)

        let actionStack = NSStackView(views: [viewModeControl, refreshButton, chooseFolderButton, newFolderButton])
        actionStack.orientation = .horizontal
        actionStack.spacing = 6
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(actionStack)

        let optionsBar = NSVisualEffectView()
        optionsBar.material = .contentBackground
        optionsBar.blendingMode = .behindWindow
        optionsBar.state = .active
        optionsBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(optionsBar)

        searchField.placeholderString = L("搜尋呢邊")
        searchField.sendsSearchStringImmediately = true
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: 11.5)
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        optionsBar.addSubview(searchField)

        sortPopUp.removeAllItems()
        FileSortOption.allCases.forEach { sortPopUp.addItem(withTitle: $0.title) }
        sortPopUp.target = self
        sortPopUp.action = #selector(sortChanged)
        sortPopUp.toolTip = L("排列方式")
        sortPopUp.controlSize = .small
        sortPopUp.font = .systemFont(ofSize: 11.5)
        sortPopUp.translatesAutoresizingMaskIntoConstraints = false
        optionsBar.addSubview(sortPopUp)

        configureButton(
            sortDirectionButton,
            symbol: "arrow.up",
            tooltip: L("由細至大"),
            action: #selector(sortDirectionChanged)
        )
        optionsBar.addSubview(sortDirectionButton)

        configureButton(
            favoriteButton,
            symbol: "star",
            tooltip: L("收藏目前資料夾"),
            action: #selector(toggleFavorite)
        )
        optionsBar.addSubview(favoriteButton)

        configureButton(
            hiddenFilesButton,
            symbol: "eye.slash",
            tooltip: L("顯示隱藏檔案"),
            action: #selector(toggleHiddenFiles)
        )
        optionsBar.addSubview(hiddenFilesButton)

        sidebarController.delegate = self
        fileTableController.delegate = self
        addChild(sidebarController)
        addChild(fileTableController)

        contentSplitView.isVertical = true
        contentSplitView.dividerStyle = .thin
        contentSplitView.autosaveName = "FinderV2-\(storageKey)-Sidebar"
        contentSplitView.translatesAutoresizingMaskIntoConstraints = false
        contentSplitView.addArrangedSubview(sidebarController.view)
        contentSplitView.addArrangedSubview(fileTableController.view)
        sidebarController.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 155).isActive = true
        sidebarController.view.widthAnchor.constraint(lessThanOrEqualToConstant: 245).isActive = true
        root.addSubview(contentSplitView)

        let statusBar = NSVisualEffectView()
        statusBar.material = .contentBackground
        statusBar.blendingMode = .behindWindow
        statusBar.state = .active
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusBar)

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(statusLabel)

        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.controlSize = .small
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(progressIndicator)

        cancelOperationButton.bezelStyle = .roundRect
        cancelOperationButton.font = .systemFont(ofSize: 11)
        cancelOperationButton.target = self
        cancelOperationButton.action = #selector(cancelCurrentOperation)
        cancelOperationButton.isHidden = true
        cancelOperationButton.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(cancelOperationButton)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 45),

            navigationStack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
            navigationStack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            navigationStack.widthAnchor.constraint(equalToConstant: 96),

            actionStack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
            actionStack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            actionStack.widthAnchor.constraint(equalToConstant: 264),

            pathControl.leadingAnchor.constraint(equalTo: navigationStack.trailingAnchor, constant: 7),
            pathControl.trailingAnchor.constraint(equalTo: actionStack.leadingAnchor, constant: -7),
            pathControl.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            addressField.leadingAnchor.constraint(equalTo: pathControl.leadingAnchor),
            addressField.trailingAnchor.constraint(equalTo: pathControl.trailingAnchor),
            addressField.centerYAnchor.constraint(equalTo: pathControl.centerYAnchor),

            optionsBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            optionsBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            optionsBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            optionsBar.heightAnchor.constraint(equalToConstant: 34),

            searchField.leadingAnchor.constraint(equalTo: optionsBar.leadingAnchor, constant: 8),
            searchField.centerYAnchor.constraint(equalTo: optionsBar.centerYAnchor),
            searchField.heightAnchor.constraint(equalToConstant: 23),

            sortPopUp.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 7),
            sortPopUp.centerYAnchor.constraint(equalTo: optionsBar.centerYAnchor),
            sortPopUp.widthAnchor.constraint(equalToConstant: 78),

            sortDirectionButton.leadingAnchor.constraint(equalTo: sortPopUp.trailingAnchor, constant: 4),
            sortDirectionButton.centerYAnchor.constraint(equalTo: optionsBar.centerYAnchor),

            hiddenFilesButton.leadingAnchor.constraint(equalTo: sortDirectionButton.trailingAnchor, constant: 4),
            hiddenFilesButton.centerYAnchor.constraint(equalTo: optionsBar.centerYAnchor),

            favoriteButton.leadingAnchor.constraint(equalTo: hiddenFilesButton.trailingAnchor, constant: 4),
            favoriteButton.trailingAnchor.constraint(equalTo: optionsBar.trailingAnchor, constant: -8),
            favoriteButton.centerYAnchor.constraint(equalTo: optionsBar.centerYAnchor),

            contentSplitView.topAnchor.constraint(equalTo: optionsBar.bottomAnchor),
            contentSplitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentSplitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentSplitView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 22),

            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 10),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: progressIndicator.leadingAnchor, constant: -7),

            progressIndicator.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            progressIndicator.widthAnchor.constraint(equalToConstant: 88),
            progressIndicator.heightAnchor.constraint(equalToConstant: 10),

            cancelOperationButton.leadingAnchor.constraint(equalTo: progressIndicator.trailingAnchor, constant: 6),
            cancelOperationButton.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -7),
            cancelOperationButton.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            cancelOperationButton.widthAnchor.constraint(equalToConstant: 44),
            cancelOperationButton.heightAnchor.constraint(equalToConstant: 20)
        ])

        self.view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let savedMode = FileViewMode(
            rawValue: UserDefaults.standard.integer(forKey: "\(storageKey)-ViewMode")
        ) ?? .list
        viewModeControl.selectedSegment = savedMode.rawValue
        fileTableController.setViewMode(savedMode)

        sortOption = FileSortOption(
            rawValue: UserDefaults.standard.integer(forKey: "\(storageKey)-SortOption")
        ) ?? .name
        sortAscending = UserDefaults.standard.object(forKey: "\(storageKey)-SortAscending") as? Bool ?? true
        showHiddenFiles = UserDefaults.standard.bool(forKey: "\(storageKey)-ShowHiddenFiles")
        sortPopUp.selectItem(at: sortOption.rawValue)
        updateSortDirectionButton()
        updateHiddenFilesButton()
        fileTableController.setDisplayOptions(
            sortOption: sortOption,
            ascending: sortAscending,
            showHiddenFiles: showHiddenFiles
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fileSystemChanged),
            name: .finderV2FileSystemChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(operationStatusChanged),
            name: .finderV2OperationStatusChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageChanged),
            name: .finderV2LanguageChanged,
            object: nil
        )
        navigate(to: initialURL, recordingHistory: true)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if contentSplitView.subviews.count == 2,
           contentSplitView.subviews[0].frame.width < 100 {
            contentSplitView.setPosition(175, ofDividerAt: 0)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func setActive(_ active: Bool) {
        view.layer?.borderWidth = 0
        statusLabel.textColor = active ? .labelColor : .secondaryLabelColor
    }

    func navigate(to url: URL, recordingHistory: Bool) {
        didActivate?(self)
        endPathEditing()
        let standardized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            showMessage(title: L("搵唔到資料夾"), message: L("呢個資料夾可能已經搬走或刪除。"))
            return
        }

        if recordingHistory,
           historyIndex >= 0,
           historyIndex < history.count,
           history[historyIndex].standardizedFileURL == standardized {
            reloadItems()
            return
        }

        currentDirectory = standardized
        startDirectoryMonitor(for: standardized)
        pathControl.url = standardized
        searchField.stringValue = ""
        updateFavoriteButton()
        sidebarController.selectLocation(matching: standardized)
        UserDefaults.standard.set(standardized.path, forKey: storageKey)

        if recordingHistory {
            if historyIndex + 1 < history.count {
                history.removeSubrange((historyIndex + 1)..<history.count)
            }
            history.append(standardized)
            historyIndex = history.count - 1
        }
        updateNavigationButtons()
        if FolderAccessStore.shared.needsPermission(for: standardized),
           !FolderAccessStore.shared.hasAccess(to: standardized) {
            allItems = []
            fileTableController.reload(items: [], currentDirectory: standardized)
            statusLabel.stringValue = L("請按資料夾按鈕允許存取")
        } else {
            reloadItems()
        }
    }

    @objc private func languageChanged() {
        applyLocalizedChrome()
        sidebarController.applyLocalization()
        fileTableController.applyLocalization()
        applyDisplayOptions()
    }

    private func applyLocalizedChrome() {
        configureButton(backButton, symbol: "chevron.left", tooltip: L("返回"), action: #selector(goBack))
        configureButton(forwardButton, symbol: "chevron.right", tooltip: L("前進"), action: #selector(goForward))
        configureButton(upButton, symbol: "arrow.up", tooltip: L("上一層"), action: #selector(goUp))
        configureButton(
            refreshButton,
            symbol: "arrow.clockwise",
            tooltip: L("重新整理"),
            action: #selector(refreshPressed),
            title: L("重新整理"),
            width: 78
        )
        configureButton(chooseFolderButton, symbol: "folder", tooltip: L("選擇資料夾"), action: #selector(chooseFolderPressed))
        configureButton(newFolderButton, symbol: "folder.badge.plus", tooltip: L("新增資料夾"), action: #selector(newFolderPressed))
        viewModeControl.setImage(
            NSImage(systemSymbolName: "list.bullet", accessibilityDescription: L("清單")),
            forSegment: FileViewMode.list.rawValue
        )
        viewModeControl.setImage(
            NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: L("大圖示")),
            forSegment: FileViewMode.icons.rawValue
        )
        viewModeControl.setImage(
            NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: L("直欄")),
            forSegment: FileViewMode.columns.rawValue
        )
        viewModeControl.setImage(
            NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: L("圖庫")),
            forSegment: FileViewMode.gallery.rawValue
        )
        viewModeControl.setToolTip(L("清單"), forSegment: FileViewMode.list.rawValue)
        viewModeControl.setToolTip(L("大圖示"), forSegment: FileViewMode.icons.rawValue)
        viewModeControl.setToolTip(L("直欄"), forSegment: FileViewMode.columns.rawValue)
        viewModeControl.setToolTip(L("圖庫"), forSegment: FileViewMode.gallery.rawValue)
        viewModeControl.setAccessibilityLabel(L("顯示方式"))
        addressField.placeholderString = L("完整路徑")
        addressField.toolTip = L("按 Command-C 複製完整路徑；Return 開啟；Escape 返回")
        addressField.setAccessibilityLabel(L("完整路徑"))
        searchField.placeholderString = L("搜尋呢邊")
        let selectedSort = sortOption
        sortPopUp.removeAllItems()
        FileSortOption.allCases.forEach { sortPopUp.addItem(withTitle: $0.title) }
        sortPopUp.selectItem(at: selectedSort.rawValue)
        sortPopUp.toolTip = L("排列方式")
        cancelOperationButton.title = L("取消")
        updateSortDirectionButton()
        updateHiddenFilesButton()
        updateFavoriteButton()
    }

    func setMonitoringEnabled(_ enabled: Bool) {
        isMonitoringEnabled = enabled
        if enabled {
            startDirectoryMonitor(for: currentDirectory)
        } else {
            directoryMonitor.stopMonitoring()
        }
    }

    private func startDirectoryMonitor(for url: URL) {
        guard isMonitoringEnabled else {
            directoryMonitor.stopMonitoring()
            return
        }
        let standardized = url.standardizedFileURL
        directoryMonitor.startMonitoring(standardized) { [weak self] in
            guard let self,
                  self.currentDirectory.standardizedFileURL == standardized else {
                return
            }
            self.reloadItems()
        }
    }

    func reloadItems() {
        let requestedDirectory = currentDirectory
        let showHidden = showHiddenFiles
        reloadRequestID += 1
        let requestedReloadID = reloadRequestID
        statusLabel.stringValue = L("載入中…")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try FileItem.load(from: requestedDirectory, showHidden: showHidden)
            }
            DispatchQueue.main.async {
                guard requestedDirectory.standardizedFileURL == self.currentDirectory.standardizedFileURL else {
                    return
                }
                guard requestedReloadID == self.reloadRequestID else { return }
                switch result {
                case .success(let items):
                    self.allItems = items
                    self.applyDisplayOptions()
                    self.sidebarController.reloadLocations()
                    self.sidebarController.selectLocation(matching: requestedDirectory)
                case .failure(let error):
                    self.statusLabel.stringValue = L("未能顯示")
                    self.showMessage(title: L("開唔到呢個資料夾"), message: ErrorMessage.text(for: error))
                }
            }
        }
    }

    func openSelectedItems() {
        fileTableController.selectedItems().forEach(open)
    }

    func copySelectedItems() {
        didActivate?(self)
        let urls = fileTableController.selectedURLs()
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls as [NSURL])
    }

    func pasteItems() {
        didActivate?(self)
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = (NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL]) ?? []
        guard !urls.isEmpty else {
            showMessage(title: L("冇檔案可以貼上"), message: L("請先複製一個或多個檔案。"))
            return
        }
        transfer(urls, to: currentDirectory, operation: .copy)
    }

    func duplicateSelectedItems() {
        didActivate?(self)
        let selected = fileTableController.selectedItems()
        guard !selected.isEmpty else { return }

        OperationStatusCenter.shared.begin(count: selected.count)
        DispatchQueue.global(qos: .userInitiated).async {
            var duplicated: [URL] = []
            var errors: [Error] = []
            for item in selected {
                let desired = item.url.deletingLastPathComponent()
                    .appendingPathComponent(item.url.lastPathComponent)
                let destination = FileTransferCoordinator.availableURL(for: desired)
                do {
                    try FileManager.default.copyItem(at: item.url, to: destination)
                    duplicated.append(destination)
                } catch {
                    errors.append(error)
                }
                OperationStatusCenter.shared.finish()
            }

            DispatchQueue.main.async {
                if !duplicated.isEmpty {
                    self.view.window?.undoManager?.registerUndo(withTarget: self) { target in
                        target.undoDuplicates(duplicated)
                    }
                    self.view.window?.undoManager?.setActionName(L("製作副本"))
                }
                if let error = errors.first {
                    self.showMessage(title: L("有副本整唔到"), message: ErrorMessage.text(for: error))
                }
                NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
            }
        }
    }

    func createFolderWithSelectedItems() {
        didActivate?(self)
        let sourceURLs = fileTableController.selectedURLs()
        guard !sourceURLs.isEmpty else { return }

        let parents = Set(sourceURLs.map { $0.deletingLastPathComponent().standardizedFileURL })
        let folderParent = parents.count == 1 ? parents.first! : currentDirectory
        let desiredFolder = folderParent.appendingPathComponent(
            L("包含項目的新資料夾"),
            isDirectory: true
        )
        let folderURL = FileTransferCoordinator.availableURL(for: desiredFolder)

        OperationStatusCenter.shared.begin(count: sourceURLs.count)
        DispatchQueue.global(qos: .userInitiated).async {
            var movedPairs: [(original: URL, insideFolder: URL)] = []
            var operationError: Error?

            do {
                try FileManager.default.createDirectory(
                    at: folderURL,
                    withIntermediateDirectories: false
                )
                for sourceURL in sourceURLs {
                    let destination = folderURL.appendingPathComponent(
                        sourceURL.lastPathComponent,
                        isDirectory: sourceURL.hasDirectoryPath
                    )
                    try FileManager.default.moveItem(at: sourceURL, to: destination)
                    movedPairs.append((sourceURL, destination))
                    OperationStatusCenter.shared.finish()
                }
            } catch {
                operationError = error
                for pair in movedPairs.reversed()
                    where FileManager.default.fileExists(atPath: pair.insideFolder.path) {
                    try? FileManager.default.moveItem(
                        at: pair.insideFolder,
                        to: pair.original
                    )
                }
                let remaining = (try? FileManager.default.contentsOfDirectory(atPath: folderURL.path)) ?? ["."]
                if remaining.isEmpty {
                    try? FileManager.default.removeItem(at: folderURL)
                }
                for _ in movedPairs.count..<sourceURLs.count {
                    OperationStatusCenter.shared.finish()
                }
            }

            DispatchQueue.main.async {
                if operationError == nil {
                    self.view.window?.undoManager?.registerUndo(withTarget: self) { target in
                        target.undoFolderWithSelection(
                            folderURL: folderURL,
                            movedPairs: movedPairs
                        )
                    }
                    self.view.window?.undoManager?.setActionName(L("新增包含項目的資料夾"))
                } else if let operationError {
                    self.showMessage(
                        title: L("新增唔到資料夾"),
                        message: ErrorMessage.text(for: operationError)
                    )
                }
                NotificationCenter.default.post(
                    name: .finderV2FileSystemChanged,
                    object: nil
                )
            }
        }
    }

    func openSelectedItems(withApplicationAt applicationURL: URL) {
        didActivate?(self)
        let urls = fileTableController.selectedURLs()
        guard !urls.isEmpty else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: configuration
        ) { [weak self] _, error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.showMessage(
                    title: L("開唔到檔案"),
                    message: ErrorMessage.text(for: error)
                )
            }
        }
    }

    func chooseApplicationForSelectedItems() {
        didActivate?(self)
        guard !fileTableController.selectedURLs().isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = L("選擇應用程式")
        panel.prompt = L("開啟")
        panel.allowedContentTypes = [.application]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let applicationURL = panel.url else { return }
        openSelectedItems(withApplicationAt: applicationURL)
    }

    func createAliasesForSelection() {
        didActivate?(self)
        let sourceURLs = fileTableController.selectedURLs()
        guard !sourceURLs.isEmpty else { return }

        OperationStatusCenter.shared.begin(count: sourceURLs.count)
        DispatchQueue.global(qos: .userInitiated).async {
            var createdURLs: [URL] = []
            var firstError: Error?

            for sourceURL in sourceURLs {
                let desiredURL = self.aliasDestination(for: sourceURL)
                let destinationURL = FileTransferCoordinator.availableURL(for: desiredURL)
                do {
                    try FileManager.default.createSymbolicLink(
                        at: destinationURL,
                        withDestinationURL: sourceURL
                    )
                    createdURLs.append(destinationURL)
                } catch {
                    firstError = firstError ?? error
                }
                OperationStatusCenter.shared.finish()
            }

            DispatchQueue.main.async {
                if !createdURLs.isEmpty {
                    self.view.window?.undoManager?.registerUndo(withTarget: self) { target in
                        target.undoCreatedItems(createdURLs)
                    }
                    self.view.window?.undoManager?.setActionName(L("製作替身"))
                }
                if let firstError {
                    self.showMessage(
                        title: L("有替身整唔到"),
                        message: ErrorMessage.text(for: firstError)
                    )
                }
                NotificationCenter.default.post(
                    name: .finderV2FileSystemChanged,
                    object: nil
                )
            }
        }
    }

    func showViewOptions() {
        didActivate?(self)

        let viewModePopUp = NSPopUpButton()
        FileViewMode.allCases.forEach { viewModePopUp.addItem(withTitle: $0.title) }
        viewModePopUp.selectItem(at: viewModeControl.selectedSegment)

        let sortPopUp = NSPopUpButton()
        FileSortOption.allCases.forEach { sortPopUp.addItem(withTitle: $0.title) }
        sortPopUp.selectItem(at: sortOption.rawValue)

        let directionPopUp = NSPopUpButton()
        directionPopUp.addItems(withTitles: [L("由細至大"), L("由大至細")])
        directionPopUp.selectItem(at: sortAscending ? 0 : 1)

        let hiddenCheckBox = NSButton(
            checkboxWithTitle: L("顯示隱藏檔案"),
            target: nil,
            action: nil
        )
        hiddenCheckBox.state = showHiddenFiles ? .on : .off

        let stack = NSStackView(views: [
            labeledControl(title: L("顯示方式"), control: viewModePopUp),
            labeledControl(title: L("排列方式"), control: sortPopUp),
            labeledControl(title: L("次序"), control: directionPopUp),
            hiddenCheckBox
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.frame = NSRect(x: 0, y: 0, width: 300, height: 150)

        let alert = NSAlert()
        alert.messageText = L("顯示選項")
        alert.accessoryView = stack
        alert.addButton(withTitle: L("套用"))
        alert.addButton(withTitle: L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let mode = FileViewMode(rawValue: viewModePopUp.indexOfSelectedItem) ?? .list
        let selectedSort = FileSortOption(rawValue: sortPopUp.indexOfSelectedItem) ?? .name
        let ascending = directionPopUp.indexOfSelectedItem == 0
        let shouldShowHiddenFiles = hiddenCheckBox.state == .on

        changeViewMode(to: mode)
        updateSorting(option: selectedSort, ascending: ascending)
        if showHiddenFiles != shouldShowHiddenFiles {
            toggleHiddenFiles()
        }
    }

    func applyTag(_ tag: FinderTag?) {
        didActivate?(self)
        let urls = fileTableController.selectedURLs()
        guard !urls.isEmpty else { return }

        OperationStatusCenter.shared.begin(count: urls.count)
        DispatchQueue.global(qos: .userInitiated).async {
            var firstError: Error?
            for url in urls {
                do {
                    try FileTagEngine.apply(tag, to: [url])
                } catch {
                    firstError = firstError ?? error
                }
                OperationStatusCenter.shared.finish()
            }
            DispatchQueue.main.async {
                if let firstError {
                    self.showMessage(
                        title: L("有標籤加唔到"),
                        message: ErrorMessage.text(for: firstError)
                    )
                }
                NotificationCenter.default.post(
                    name: .finderV2FileSystemChanged,
                    object: nil
                )
            }
        }
    }

    func toggleQuickLook() {
        didActivate?(self)
        let urls = fileTableController.selectedURLs()
        guard !urls.isEmpty else { return }
        guard let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible, panel.dataSource === self {
            panel.orderOut(nil)
            return
        }

        quickLookURLs = urls
        panel.dataSource = self
        panel.delegate = self
        panel.currentPreviewItemIndex = 0
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func showSelectedItemInfo() {
        didActivate?(self)
        guard let item = fileTableController.selectedItems().first else { return }
        let alert = NSAlert()
        alert.messageText = item.name
        alert.informativeText = String(
            format: L("種類：%@\n大小：%@\n修改日期：%@\n位置：%@"),
            item.kind,
            FileFormatting.size(for: item),
            FileFormatting.date(item.modifiedDate),
            item.url.deletingLastPathComponent().path
        )
        alert.addButton(withTitle: L("知道"))
        alert.runModal()
    }

    func copySelectedPaths() {
        didActivate?(self)
        let paths = fileTableController.selectedURLs().map(\.path)
        guard !paths.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    func pathContextMenuTitlesForTesting() -> [String] {
        makePathContextMenu(for: currentDirectory).items.map { item in
            item.isSeparatorItem ? "—" : item.title
        }
    }

    private func makePathContextMenu(for url: URL) -> NSMenu {
        let folderName = FileManager.default.displayName(atPath: url.path)
        let menu = NSMenu(title: folderName)

        addPathMenuItem(
            to: menu,
            title: String(format: L("拷貝「%@」"), folderName),
            action: #selector(copyPathItem),
            representedObject: url
        )
        addPathMenuItem(
            to: menu,
            title: L("複製路徑"),
            action: #selector(copyPathItemText),
            representedObject: url
        )
        addPathMenuItem(
            to: menu,
            title: L("在 Apple Finder 顯示"),
            action: #selector(revealPathItem),
            representedObject: url
        )
        menu.addItem(.separator())
        addPathMenuItem(
            to: menu,
            title: L("取得資料"),
            action: #selector(showPathItemInfo),
            representedObject: url
        )
        return menu
    }

    private func addPathMenuItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        representedObject: URL
    ) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
    }

    @objc private func copyPathItem(_ sender: NSMenuItem) {
        didActivate?(self)
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([url as NSURL])
    }

    @objc private func copyPathItemText(_ sender: NSMenuItem) {
        didActivate?(self)
        guard let url = sender.representedObject as? URL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    @objc private func revealPathItem(_ sender: NSMenuItem) {
        didActivate?(self)
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func showPathItemInfo(_ sender: NSMenuItem) {
        didActivate?(self)
        guard let url = sender.representedObject as? URL else { return }
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let size = values?.fileSize.map {
            FileFormatting.byteFormatter.string(fromByteCount: Int64($0))
        } ?? "—"
        let modified = values?.contentModificationDate.map {
            FileFormatting.date($0)
        } ?? "—"
        let alert = NSAlert()
        alert.messageText = FileManager.default.displayName(atPath: url.path)
        alert.informativeText = String(
            format: L("種類：資料夾\n大小：%@\n修改日期：%@\n位置：%@"),
            size,
            modified,
            url.deletingLastPathComponent().path
        )
        alert.addButton(withTitle: L("知道"))
        alert.runModal()
    }

    func revealSelectedItemsInFinder() {
        didActivate?(self)
        let urls = fileTableController.selectedURLs()
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func createNewFolder() {
        didActivate?(self)
        let input = NSTextField(string: L("未命名資料夾"))
        input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        input.selectText(nil)

        let alert = NSAlert()
        alert.messageText = L("新增資料夾")
        alert.informativeText = L("輸入資料夾名稱：")
        alert.accessoryView = input
        alert.addButton(withTitle: L("新增"))
        alert.addButton(withTitle: L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidFileName(name) else {
            showMessage(title: L("名稱唔可以用"), message: L("名稱唔可以係空白，亦唔可以有「/」。"))
            return
        }

        let newFolder = currentDirectory.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: newFolder.path) else {
            showMessage(title: L("已有同名項目"), message: L("請用另一個名稱。"))
            return
        }

        do {
            try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: false)
            view.window?.undoManager?.registerUndo(withTarget: self) { target in
                target.undoNewFolder(at: newFolder)
            }
            view.window?.undoManager?.setActionName(L("新增資料夾"))
            reloadItems()
        } catch {
            showMessage(title: L("新增唔到資料夾"), message: ErrorMessage.text(for: error))
        }
    }

    func chooseFolder(suggestedURL: URL? = nil) {
        didActivate?(self)
        let panel = NSOpenPanel()
        panel.title = L("選擇要顯示嘅資料夾")
        panel.message = L("第一次使用呢個位置，需要你確認一次。")
        panel.prompt = L("使用呢個資料夾")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = suggestedURL ?? currentDirectory

        guard panel.runModal() == .OK, let chosenURL = panel.url else { return }
        do {
            try FolderAccessStore.shared.grantAccess(to: chosenURL)
            navigate(to: chosenURL, recordingHistory: true)
        } catch {
            showMessage(title: L("未能記住呢個資料夾"), message: ErrorMessage.text(for: error))
        }
    }

    func renameSelectedItem() {
        didActivate?(self)
        let selected = fileTableController.selectedItems()
        if selected.count > 1 {
            batchRenameSelectedItems()
            return
        }
        guard selected.count == 1, let item = selected.first else {
            showMessage(title: L("請揀一個項目"), message: L("每次只可以幫一個檔案或資料夾改名。"))
            return
        }

        let currentName = item.url.lastPathComponent
        let input = NSTextField(string: currentName)
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        input.selectText(nil)

        let alert = NSAlert()
        alert.messageText = L("改名")
        alert.informativeText = L("輸入新名稱：")
        alert.accessoryView = input
        alert.addButton(withTitle: L("改名"))
        alert.addButton(withTitle: L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let newName = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidFileName(newName) else {
            showMessage(title: L("名稱唔可以用"), message: L("名稱唔可以係空白，亦唔可以有「/」。"))
            return
        }
        guard newName != currentName else { return }

        let destination = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        if FileRenameSupport.existsAsDifferentItem(destination, source: item.url) {
            showMessage(title: L("已有同名項目"), message: L("請用另一個名稱。"))
            return
        }

        do {
            try FileRenameSupport.moveItem(from: item.url, to: destination)
            view.window?.undoManager?.registerUndo(withTarget: self) { target in
                target.undoRename(from: destination, to: item.url)
            }
            view.window?.undoManager?.setActionName(L("改名"))
            NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
        } catch {
            showMessage(title: L("改唔到名"), message: ErrorMessage.text(for: error))
        }
    }

    func batchRenameSelectedItems() {
        didActivate?(self)
        let selected = fileTableController.selectedItems().sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        guard selected.count > 1 else {
            showMessage(title: L("請揀多個項目"), message: L("揀兩個或以上檔案，先可以批量改名。"))
            return
        }

        let modePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        BatchRenameMode.allCases.forEach { modePopUp.addItem(withTitle: $0.title) }
        let firstField = NSTextField(string: "")
        firstField.placeholderString = L("要加嘅字／要搵嘅字／新名稱")
        let secondField = NSTextField(string: "")
        secondField.placeholderString = L("取代成（只限搵字及取代）")
        let stack = NSStackView(views: [modePopUp, firstField, secondField])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 330, height: 88)

        let alert = NSAlert()
        alert.messageText = L("批量改名")
        alert.informativeText = L("揀方法，再輸入文字：")
        alert.accessoryView = stack
        alert.addButton(withTitle: L("預覽及改名"))
        alert.addButton(withTitle: L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let mode = BatchRenameMode(rawValue: modePopUp.indexOfSelectedItem) ?? .prefix
        let firstText = firstField.stringValue
        guard !firstText.isEmpty else {
            showMessage(title: L("未有文字"), message: L("請輸入要加、要搵或新名稱。"))
            return
        }
        let names = BatchRenameEngine.proposedNames(
            for: selected,
            mode: mode,
            firstText: firstText,
            secondText: secondField.stringValue
        )
        guard names.allSatisfy(isValidFileName) else {
            showMessage(title: L("名稱唔可以用"), message: L("名稱唔可以係空白，亦唔可以有「/」。"))
            return
        }

        var namesByParent: [String: Set<String>] = [:]
        for (item, name) in zip(selected, names) {
            let parent = item.url.deletingLastPathComponent().standardizedFileURL.path
            var used = namesByParent[parent] ?? []
            if !used.insert(name.lowercased()).inserted {
                showMessage(title: L("新名稱有重複"), message: L("請改一改設定，再試一次。"))
                return
            }
            namesByParent[parent] = used
        }

        let finalURLs = zip(selected, names).map { item, name in
            item.url.deletingLastPathComponent().appendingPathComponent(name)
        }
        guard zip(selected, finalURLs).allSatisfy({ item, finalURL in
            if !FileManager.default.fileExists(atPath: finalURL.path) { return true }
            return FileRenameSupport.isSameItem(item.url, as: finalURL)
                || selected.contains { $0.url.standardizedFileURL == finalURL.standardizedFileURL }
        }) else {
            showMessage(title: L("已有同名項目"), message: L("請改一改設定，避免撞名。"))
            return
        }

        let preview = zip(selected, names).prefix(8)
            .map { "\($0.0.name)  →  \($0.1)" }
            .joined(separator: "\n")
        let confirm = NSAlert()
        confirm.messageText = String(format: L("確認改 %ld 個名稱？"), selected.count)
        confirm.informativeText = preview + (selected.count > 8 ? "\n…" : "")
        confirm.addButton(withTitle: L("改名"))
        confirm.addButton(withTitle: L("取消"))
        guard confirm.runModal() == .alertFirstButtonReturn else { return }

        do {
            let undoPairs = try BatchRenameEngine.apply(items: selected, names: names)
            view.window?.undoManager?.registerUndo(withTarget: self) { target in
                target.undoBatchRename(undoPairs)
            }
            view.window?.undoManager?.setActionName(L("批量改名"))
            NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
        } catch {
            reloadItems()
            showMessage(title: L("有項目改唔到名"), message: ErrorMessage.text(for: error))
        }
    }

    func createZipFromSelection() {
        didActivate?(self)
        let urls = fileTableController.selectedURLs()
        guard !urls.isEmpty else {
            showMessage(title: L("未揀檔案"), message: L("請先揀要壓縮嘅檔案。"))
            return
        }
        let defaultName = urls.count == 1
            ? urls[0].deletingPathExtension().lastPathComponent
            : L("壓縮檔")
        let input = NSTextField(string: defaultName)
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        let alert = NSAlert()
        alert.messageText = L("壓縮成 ZIP")
        alert.informativeText = L("輸入 ZIP 名稱：")
        alert.accessoryView = input
        alert.addButton(withTitle: L("壓縮"))
        alert.addButton(withTitle: L("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidFileName(name) else { return }

        OperationStatusCenter.shared.begin()
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try ArchiveEngine.createZip(from: urls, in: self.currentDirectory, named: name)
            }
            OperationStatusCenter.shared.finish()
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    self.showMessage(title: L("壓縮唔到"), message: ErrorMessage.text(for: error))
                }
                NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
            }
        }
    }

    func extractSelectedZipFiles() {
        didActivate?(self)
        let urls = fileTableController.selectedURLs().filter {
            $0.pathExtension.lowercased() == "zip"
        }
        guard !urls.isEmpty else {
            showMessage(title: L("未揀 ZIP"), message: L("請先揀一個或多個 ZIP 檔案。"))
            return
        }
        OperationStatusCenter.shared.begin(count: urls.count)
        DispatchQueue.global(qos: .userInitiated).async {
            var firstError: Error?
            for url in urls {
                do {
                    _ = try ArchiveEngine.extractZip(url, to: self.currentDirectory)
                } catch {
                    firstError = firstError ?? error
                }
                OperationStatusCenter.shared.finish()
            }
            DispatchQueue.main.async {
                if let firstError {
                    self.showMessage(title: L("有 ZIP 解唔到"), message: ErrorMessage.text(for: firstError))
                }
                NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
            }
        }
    }

    func downloadSelectedCloudItems() {
        didActivate?(self)
        let urls = fileTableController.selectedItems()
            .filter { $0.cloudAvailability == .onlineOnly || $0.cloudAvailability == .downloading }
            .map(\.url)
        guard !urls.isEmpty else {
            showMessage(title: L("已經在本機"), message: L("所選檔案唔需要另外下載。"))
            return
        }
        OperationStatusCenter.shared.begin(count: urls.count)
        DispatchQueue.global(qos: .userInitiated).async {
            var firstError: Error?
            for url in urls {
                do {
                    try FileManager.default.startDownloadingUbiquitousItem(at: url)
                } catch {
                    do {
                        let handle = try FileHandle(forReadingFrom: url)
                        _ = try handle.read(upToCount: 1)
                        try handle.close()
                    } catch {
                        firstError = firstError ?? error
                    }
                }
                OperationStatusCenter.shared.finish()
            }
            DispatchQueue.main.async {
                if let firstError {
                    self.showMessage(title: L("下載唔到"), message: ErrorMessage.text(for: firstError))
                }
                self.reloadItems()
            }
        }
    }

    func showComparison(_ states: [String: FolderComparisonState]) {
        fileTableController.showComparison(states)
    }

    func clearComparison() {
        fileTableController.clearComparison()
    }

    func copyForSync(_ urls: [URL], to destination: URL, completion: (() -> Void)? = nil) {
        FileTransferCoordinator.shared.transfer(
            sources: urls,
            to: destination,
            operation: .copy,
            undoManager: view.window?.undoManager,
            collisionChoice: .replace,
            completion: completion
        )
    }

    func copyForSync(_ operations: [SyncOperation], completion: (() -> Void)? = nil) {
        let groups = Dictionary(grouping: operations) {
            $0.destinationFolder.standardizedFileURL.path
        }
        let destinations = Array(groups.keys)
        func run(_ index: Int) {
            guard index < destinations.count else {
                completion?()
                return
            }
            let destination = URL(fileURLWithPath: destinations[index], isDirectory: true)
            let urls = groups[destinations[index]]?.map(\.source) ?? []
            FileTransferCoordinator.shared.transfer(
                sources: urls,
                to: destination,
                operation: .copy,
                undoManager: view.window?.undoManager,
                collisionChoice: .replace,
                completion: { run(index + 1) }
            )
        }
        run(0)
    }

    func moveSelectedItemsToTrash() {
        didActivate?(self)
        let urls = fileTableController.selectedURLs()
        guard !urls.isEmpty else {
            showMessage(title: L("未揀檔案"), message: L("請先揀要搬去垃圾桶嘅項目。"))
            return
        }

        OperationStatusCenter.shared.begin(count: urls.count)
        DispatchQueue.global(qos: .userInitiated).async {
            var moved: [(original: URL, trashed: URL)] = []
            var errors: [Error] = []
            for url in urls {
                do {
                    var trashedNSURL: NSURL?
                    try FileManager.default.trashItem(at: url, resultingItemURL: &trashedNSURL)
                    if let trashedURL = trashedNSURL as URL? {
                        moved.append((url, trashedURL))
                    } else if FileManager.default.fileExists(atPath: url.path) {
                        errors.append(FileOperationError.undoSourceMissing)
                    }
                } catch {
                    errors.append(error)
                }
                OperationStatusCenter.shared.finish()
            }
            DispatchQueue.main.async {
                if !moved.isEmpty {
                    self.view.window?.undoManager?.registerUndo(withTarget: self) { target in
                        target.undoTrash(moved)
                    }
                    self.view.window?.undoManager?.setActionName(L("搬去垃圾桶"))
                }
                if let error = errors.first {
                    self.showMessage(title: L("有項目搬唔到"), message: ErrorMessage.text(for: error))
                }
                NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
            }
        }
    }

    @objc private func goBack() {
        moveHistory(step: -1)
    }

    @objc private func goForward() {
        moveHistory(step: 1)
    }

    private func moveHistory(step: Int) {
        var newIndex = historyIndex + step
        while newIndex >= 0, newIndex < history.count {
            let target = history[newIndex]
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: target.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                navigate(to: target, recordingHistory: false)
                guard currentDirectory.standardizedFileURL == target.standardizedFileURL else {
                    return
                }
                historyIndex = newIndex
                updateNavigationButtons()
                return
            }
            newIndex += step
        }
    }

    @objc private func goUp() {
        let parent = currentDirectory.deletingLastPathComponent()
        guard parent.path != currentDirectory.path else { return }
        navigate(to: parent, recordingHistory: true)
    }

    @objc private func refreshPressed() {
        didActivate?(self)
        reloadItems()
    }

    @objc private func newFolderPressed() {
        createNewFolder()
    }

    @objc private func chooseFolderPressed() {
        chooseFolder()
    }

    @objc private func viewModeChanged() {
        didActivate?(self)
        let mode = FileViewMode(rawValue: viewModeControl.selectedSegment) ?? .list
        changeViewMode(to: mode)
    }

    @objc private func searchChanged() {
        didActivate?(self)
        applyDisplayOptions()
    }

    @objc private func sortChanged() {
        didActivate?(self)
        updateSorting(
            option: FileSortOption(rawValue: sortPopUp.indexOfSelectedItem) ?? .name,
            ascending: sortAscending
        )
    }

    @objc private func sortDirectionChanged() {
        didActivate?(self)
        updateSorting(option: sortOption, ascending: !sortAscending)
    }

    @objc private func toggleHiddenFiles() {
        didActivate?(self)
        showHiddenFiles.toggle()
        UserDefaults.standard.set(showHiddenFiles, forKey: "\(storageKey)-ShowHiddenFiles")
        updateHiddenFilesButton()
        fileTableController.setDisplayOptions(
            sortOption: sortOption,
            ascending: sortAscending,
            showHiddenFiles: showHiddenFiles
        )
        reloadItems()
    }

    @objc private func toggleFavorite() {
        didActivate?(self)
        if FavoriteStore.shared.urls.contains(where: {
            $0.standardizedFileURL == currentDirectory.standardizedFileURL
        }) {
            FavoriteStore.shared.remove(currentDirectory)
        } else {
            FavoriteStore.shared.add(currentDirectory)
        }
        sidebarController.reloadLocations()
        sidebarController.selectLocation(matching: currentDirectory)
        updateFavoriteButton()
    }

    private func beginPathEditing(for url: URL) {
        didActivate?(self)
        guard !isEditingPath else { return }
        isEditingPath = true
        addressField.stringValue = url.standardizedFileURL.path
        pathControl.isHidden = true
        addressField.isHidden = false
        view.window?.makeFirstResponder(addressField)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEditingPath else { return }
            self.addressField.selectText(nil)
        }
    }

    private func beginPathEditing() {
        beginPathEditing(for: currentDirectory)
    }

    private func showPath(for clickedURL: URL?) {
        beginPathEditing(for: clickedURL ?? currentDirectory)
    }

    private func endPathEditing() {
        guard isEditingPath else { return }
        isEditingPath = false
        addressField.resignFirstResponder()
        addressField.isHidden = true
        pathControl.isHidden = false
    }

    @objc private func pathEditingCommitted() {
        let typedPath = addressField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typedPath.isEmpty else {
            endPathEditing()
            return
        }

        let expandedPath = (typedPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            showMessage(title: L("搵唔到資料夾"), message: L("請輸入一條存在嘅資料夾路徑。"))
            addressField.becomeFirstResponder()
            addressField.selectText(nil)
            return
        }

        endPathEditing()
        navigate(to: url, recordingHistory: true)
    }

    func beginPathEditingForTesting() {
        beginPathEditing()
    }

    func beginPathEditingForTesting(url: URL) {
        beginPathEditing(for: url)
    }

    func showPathForTesting(clickedURL: URL?) {
        showPath(for: clickedURL)
    }

    func cancelPathEditingForTesting() {
        endPathEditing()
    }

    var isPathEditingForTesting: Bool {
        isEditingPath
    }

    var addressFieldTextForTesting: String {
        addressField.stringValue
    }
    @objc private func pathControlClicked() {
        showPath(for: pathControl.clickedPathItem?.url)
    }

    @objc private func fileSystemChanged() {
        reloadItems()
    }

    @objc private func operationStatusChanged() {
        if let progress = OperationStatusCenter.shared.progressSnapshot {
            progressIndicator.isHidden = false
            cancelOperationButton.isHidden = false
            cancelOperationButton.isEnabled = !progress.isCancellationRequested
            progressIndicator.doubleValue = progress.fractionCompleted

            let completed = min(progress.totalItems, progress.completedItems + 1)
            var parts = [String(format: L("處理緊 %ld/%ld"), completed, progress.totalItems)]
            if progress.totalBytes > 0 {
                parts.append("\(Int(progress.fractionCompleted * 100))%")
                let speed = Int64(progress.bytesPerSecond)
                if speed > 0 {
                    parts.append(String(format: L("%@/秒"), FileFormatting.byteFormatter.string(fromByteCount: speed)))
                }
                if let remaining = progress.estimatedRemaining, remaining.isFinite {
                    parts.append(String(format: L("約 %ld 秒"), max(1, Int(remaining.rounded()))))
                }
            }
            statusLabel.stringValue = progress.isCancellationRequested
                ? L("正在停止…")
                : parts.joined(separator: " · ")
        } else if OperationStatusCenter.shared.isBusy {
            progressIndicator.isHidden = true
            cancelOperationButton.isHidden = true
            statusLabel.stringValue = L("正在處理檔案…")
        } else {
            progressIndicator.isHidden = true
            cancelOperationButton.isHidden = true
            applyDisplayOptions()
        }
    }

    @objc private func cancelCurrentOperation() {
        OperationStatusCenter.shared.requestCancellation()
        TransferQueueCenter.shared.cancelRunning()
    }

    private func applyDisplayOptions() {
        let displayedItems = FileDisplayArrangement.items(
            from: allItems,
            matching: searchField.stringValue,
            sortedBy: sortOption,
            ascending: sortAscending,
            sourceIsPresortedByNameAscending: true
        )
        fileTableController.setDisplayOptions(
            sortOption: sortOption,
            ascending: sortAscending,
            showHiddenFiles: showHiddenFiles
        )
        fileTableController.reload(items: displayedItems, currentDirectory: currentDirectory)
        if OperationStatusCenter.shared.isBusy {
            statusLabel.stringValue = L("正在處理檔案…")
        } else if searchField.stringValue.isEmpty {
            statusLabel.stringValue = String(format: L("%ld 個項目"), displayedItems.count)
        } else {
            statusLabel.stringValue = String(format: L("搵到 %ld / %ld 個"), displayedItems.count, allItems.count)
        }
    }

    private func updateSortDirectionButton() {
        let symbol = sortAscending ? "arrow.up" : "arrow.down"
        let description = sortAscending ? L("由細至大") : L("由大至細")
        sortDirectionButton.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: description
        )
        sortDirectionButton.toolTip = description
    }

    private func updateSorting(option: FileSortOption, ascending: Bool) {
        sortOption = option
        sortAscending = ascending
        sortPopUp.selectItem(at: option.rawValue)
        UserDefaults.standard.set(option.rawValue, forKey: "\(storageKey)-SortOption")
        UserDefaults.standard.set(ascending, forKey: "\(storageKey)-SortAscending")
        updateSortDirectionButton()
        applyDisplayOptions()
    }

    private func changeViewMode(to mode: FileViewMode) {
        viewModeControl.selectedSegment = mode.rawValue
        fileTableController.setViewMode(mode)
        UserDefaults.standard.set(mode.rawValue, forKey: "\(storageKey)-ViewMode")
    }

    private func updateFavoriteButton() {
        let isFavorite = FavoriteStore.shared.urls.contains {
            $0.standardizedFileURL == currentDirectory.standardizedFileURL
        }
        favoriteButton.image = NSImage(
            systemSymbolName: isFavorite ? "star.fill" : "star",
            accessibilityDescription: isFavorite ? L("取消收藏") : L("收藏目前資料夾")
        )
        favoriteButton.toolTip = isFavorite ? L("取消收藏") : L("收藏目前資料夾")
    }

    private func updateHiddenFilesButton() {
        hiddenFilesButton.image = NSImage(
            systemSymbolName: showHiddenFiles ? "eye" : "eye.slash",
            accessibilityDescription: showHiddenFiles ? L("隱藏隱藏檔案") : L("顯示隱藏檔案")
        )
        hiddenFilesButton.toolTip = showHiddenFiles ? L("隱藏隱藏檔案") : L("顯示隱藏檔案")
    }

    private func open(_ item: FileItem) {
        didActivate?(self)
        if item.shouldOpenAsFolder {
            navigate(to: item.url, recordingHistory: true)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    private func transfer(_ urls: [URL], to destination: URL, operation: FileTransferOperation) {
        didActivate?(self)
        FileTransferCoordinator.shared.transfer(
            sources: urls,
            to: destination,
            operation: operation,
            undoManager: view.window?.undoManager
        )
    }

    private func updateNavigationButtons() {
        backButton.isEnabled = historyIndex > 0
        forwardButton.isEnabled = historyIndex + 1 < history.count
        upButton.isEnabled = currentDirectory.path != "/"
    }

    private func configureButton(
        _ button: NSButton,
        symbol: String,
        tooltip: String,
        action: Selector,
        title: String? = nil,
        width: CGFloat = 28
    ) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.title = title ?? ""
        button.imagePosition = title == nil ? .imageOnly : .imageLeading
        button.imageHugsTitle = true
        button.alignment = .center
        button.bezelStyle = .accessoryBarAction
        button.controlSize = .regular
        button.contentTintColor = .labelColor
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width).isActive = true
        button.heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    private func makeButton(
        symbol: String,
        tooltip: String,
        action: Selector,
        title: String? = nil,
        width: CGFloat = 28
    ) -> NSButton {
        let button = NSButton()
        configureButton(
            button,
            symbol: symbol,
            tooltip: tooltip,
            action: action,
            title: title,
            width: width
        )
        return button
    }

    var refreshButtonTitleForTesting: String {
        refreshButton.title
    }

    var refreshButtonIsVisibleForTesting: Bool {
        refreshButton.superview != nil && !refreshButton.isHidden
    }

    private func labeledControl(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.widthAnchor.constraint(equalToConstant: 70).isActive = true
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 10
        return row
    }

    private func aliasDestination(for sourceURL: URL) -> URL {
        let parent = sourceURL.deletingLastPathComponent()
        let pathExtension = sourceURL.pathExtension
        if pathExtension.isEmpty || sourceURL.hasDirectoryPath {
            return parent.appendingPathComponent("\(sourceURL.lastPathComponent)" + L(" 的替身"))
        }
        let name = sourceURL.deletingPathExtension().lastPathComponent
        return parent
            .appendingPathComponent("\(name)" + L(" 的替身"))
            .appendingPathExtension(pathExtension)
    }

    private func isValidFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/")
    }

    private func undoFolderWithSelection(
        folderURL: URL,
        movedPairs: [(original: URL, insideFolder: URL)]
    ) {
        do {
            guard movedPairs.allSatisfy({
                !FileManager.default.fileExists(atPath: $0.original.path)
            }) else {
                throw FileOperationError.undoDestinationOccupied
            }
            for pair in movedPairs {
                try FileManager.default.moveItem(
                    at: pair.insideFolder,
                    to: pair.original
                )
            }
            let remaining = try FileManager.default.contentsOfDirectory(atPath: folderURL.path)
            if remaining.isEmpty {
                try FileManager.default.removeItem(at: folderURL)
            }
            NotificationCenter.default.post(
                name: .finderV2FileSystemChanged,
                object: nil
            )
        } catch {
            showMessage(title: L("未能還原"), message: ErrorMessage.text(for: error))
        }
    }

    private func undoCreatedItems(_ urls: [URL]) {
        do {
            for url in urls where FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            NotificationCenter.default.post(
                name: .finderV2FileSystemChanged,
                object: nil
            )
        } catch {
            showMessage(title: L("未能還原"), message: ErrorMessage.text(for: error))
        }
    }

    private func undoNewFolder(at url: URL) {
        do {
            let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
            guard contents.isEmpty else { throw FileOperationError.folderNotEmpty }
            var ignored: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &ignored)
            NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
        } catch {
            showMessage(title: L("未能還原"), message: ErrorMessage.text(for: error))
        }
    }

    private func undoRename(from currentURL: URL, to oldURL: URL) {
        do {
            guard !FileManager.default.fileExists(atPath: oldURL.path) else {
                throw FileOperationError.undoDestinationOccupied
            }
            try FileRenameSupport.moveItem(from: currentURL, to: oldURL)
            view.window?.undoManager?.registerUndo(withTarget: self) { target in
                target.undoRename(from: oldURL, to: currentURL)
            }
            view.window?.undoManager?.setActionName(L("改名"))
            NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
        } catch {
            showMessage(title: L("未能還原"), message: ErrorMessage.text(for: error))
        }
    }

    private func undoTrash(_ moved: [(original: URL, trashed: URL)]) {
        do {
            for pair in moved {
                guard !FileManager.default.fileExists(atPath: pair.original.path) else {
                    throw FileOperationError.undoDestinationOccupied
                }
                try FileManager.default.moveItem(at: pair.trashed, to: pair.original)
            }
            NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
        } catch {
            showMessage(title: L("未能還原"), message: ErrorMessage.text(for: error))
        }
    }

    private func undoDuplicates(_ urls: [URL]) {
        do {
            for url in urls where FileManager.default.fileExists(atPath: url.path) {
                var ignored: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &ignored)
            }
            NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
        } catch {
            showMessage(title: L("未能還原"), message: ErrorMessage.text(for: error))
        }
    }

    private func undoBatchRename(_ pairs: [(old: URL, new: URL)]) {
        do {
            let reversedItems = pairs.reversed().compactMap { pair -> FileItem? in
                FileItem.loadItem(at: pair.new)
            }
            let originalNames = pairs.reversed().map { $0.old.lastPathComponent }
            guard reversedItems.count == pairs.count else {
                throw FileOperationError.undoSourceMissing
            }
            _ = try BatchRenameEngine.apply(items: reversedItems, names: originalNames)
            NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
        } catch {
            showMessage(title: L("未能還原"), message: ErrorMessage.text(for: error))
        }
    }

    private func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L("知道"))
        alert.runModal()
    }
}

extension PaneViewController: SidebarViewControllerDelegate {
    func sidebar(_ sidebar: SidebarViewController, didChoose location: SidebarLocation) {
        if FolderAccessStore.shared.needsPermission(for: location.url),
           !FolderAccessStore.shared.hasAccess(to: location.url) {
            chooseFolder(suggestedURL: location.url)
        } else {
            navigate(to: location.url, recordingHistory: true)
        }
    }

    func sidebar(
        _ sidebar: SidebarViewController,
        didReceive urls: [URL],
        at destination: URL,
        operation: FileTransferOperation
    ) {
        transfer(urls, to: destination, operation: operation)
    }
}

extension PaneViewController: FileTableViewControllerDelegate {
    func fileTableDidActivate(_ controller: FileTableViewController) {
        didActivate?(self)
    }

    func fileTable(_ controller: FileTableViewController, didOpen item: FileItem) {
        open(item)
    }

    func fileTable(
        _ controller: FileTableViewController,
        didReceive urls: [URL],
        at destination: URL,
        operation: FileTransferOperation
    ) {
        transfer(urls, to: destination, operation: operation)
    }

    func fileTableDidRequestRename(_ controller: FileTableViewController) {
        renameSelectedItem()
    }

    func fileTableDidRequestBatchRename(_ controller: FileTableViewController) {
        batchRenameSelectedItems()
    }

    func fileTableDidRequestCreateZip(_ controller: FileTableViewController) {
        createZipFromSelection()
    }

    func fileTableDidRequestExtractZip(_ controller: FileTableViewController) {
        extractSelectedZipFiles()
    }

    func fileTableDidRequestCloudDownload(_ controller: FileTableViewController) {
        downloadSelectedCloudItems()
    }

    func fileTableDidRequestTrash(_ controller: FileTableViewController) {
        moveSelectedItemsToTrash()
    }

    func fileTableDidRequestPreview(_ controller: FileTableViewController) {
        toggleQuickLook()
    }

    func fileTableDidRequestCopy(_ controller: FileTableViewController) {
        copySelectedItems()
    }

    func fileTableDidRequestPaste(_ controller: FileTableViewController) {
        pasteItems()
    }

    func fileTableDidRequestDuplicate(_ controller: FileTableViewController) {
        duplicateSelectedItems()
    }

    func fileTableDidRequestInfo(_ controller: FileTableViewController) {
        showSelectedItemInfo()
    }

    func fileTableDidRequestCopyPath(_ controller: FileTableViewController) {
        copySelectedPaths()
    }

    func fileTableDidRequestReveal(_ controller: FileTableViewController) {
        revealSelectedItemsInFinder()
    }

    func fileTable(
        _ controller: FileTableViewController,
        didRequestSortBy option: FileSortOption,
        ascending: Bool
    ) {
        didActivate?(self)
        updateSorting(option: option, ascending: ascending)
    }

    func fileTable(
        _ controller: FileTableViewController,
        didRequestViewMode mode: FileViewMode
    ) {
        didActivate?(self)
        changeViewMode(to: mode)
    }

    func fileTableDidRequestNewFolder(_ controller: FileTableViewController) {
        createNewFolder()
    }

    func fileTableDidRequestFolderWithSelection(
        _ controller: FileTableViewController
    ) {
        createFolderWithSelectedItems()
    }

    func fileTable(
        _ controller: FileTableViewController,
        didRequestOpenWith applicationURL: URL
    ) {
        openSelectedItems(withApplicationAt: applicationURL)
    }

    func fileTableDidRequestChooseApplication(
        _ controller: FileTableViewController
    ) {
        chooseApplicationForSelectedItems()
    }

    func fileTableDidRequestAlias(_ controller: FileTableViewController) {
        createAliasesForSelection()
    }

    func fileTableDidRequestShowViewOptions(
        _ controller: FileTableViewController
    ) {
        showViewOptions()
    }

    func fileTableDidRequestToggleHiddenFiles(
        _ controller: FileTableViewController
    ) {
        toggleHiddenFiles()
    }

    func fileTable(
        _ controller: FileTableViewController,
        didRequestTag tag: FinderTag?
    ) {
        applyTag(tag)
    }
}

extension PaneViewController: QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        quickLookURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0, index < quickLookURLs.count else { return nil }
        return quickLookURLs[index] as NSURL
    }
}
