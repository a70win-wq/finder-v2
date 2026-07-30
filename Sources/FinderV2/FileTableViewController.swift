import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

enum FileViewMode: Int, CaseIterable {
    case list
    case icons
    case columns
    case gallery

    var title: String {
        switch self {
        case .list: return "清單"
        case .icons: return "大圖示"
        case .columns: return "直欄"
        case .gallery: return "圖庫"
        }
    }
}

enum FileContextMenuCommand: Equatable {
    case separator
    case newFolder
    case paste
    case viewMode
    case sort
    case showViewOptions
    case toggleHiddenFiles
    case folderWithSelection
    case open
    case openWith
    case trash
    case info
    case rename
    case compress
    case duplicate
    case alias
    case preview
    case copy
    case share
    case tags
    case extractZip
    case cloudDownload
    case copyPath
    case revealInFinder
}

struct FileContextMenuPlanItem: Equatable {
    let command: FileContextMenuCommand
    let isEnabled: Bool

    init(_ command: FileContextMenuCommand, isEnabled: Bool = true) {
        self.command = command
        self.isEnabled = isEnabled
    }
}

struct FileContextMenuPlan: Equatable {
    let items: [FileContextMenuPlanItem]

    static func make(
        selectionCount: Int,
        containsZip: Bool,
        containsCloudItem: Bool,
        clipboardHasFiles: Bool
    ) -> FileContextMenuPlan {
        guard selectionCount > 0 else {
            return FileContextMenuPlan(items: [
                FileContextMenuPlanItem(.newFolder),
                FileContextMenuPlanItem(.paste, isEnabled: clipboardHasFiles),
                FileContextMenuPlanItem(.separator),
                FileContextMenuPlanItem(.viewMode),
                FileContextMenuPlanItem(.sort),
                FileContextMenuPlanItem(.showViewOptions),
                FileContextMenuPlanItem(.toggleHiddenFiles)
            ])
        }

        var items = [
            FileContextMenuPlanItem(.folderWithSelection),
            FileContextMenuPlanItem(.open),
            FileContextMenuPlanItem(.openWith),
            FileContextMenuPlanItem(.separator),
            FileContextMenuPlanItem(.trash),
            FileContextMenuPlanItem(.separator),
            FileContextMenuPlanItem(.info),
            FileContextMenuPlanItem(.rename),
            FileContextMenuPlanItem(.compress),
            FileContextMenuPlanItem(.duplicate),
            FileContextMenuPlanItem(.alias),
            FileContextMenuPlanItem(.preview),
            FileContextMenuPlanItem(.copy),
            FileContextMenuPlanItem(.separator),
            FileContextMenuPlanItem(.share),
            FileContextMenuPlanItem(.separator),
            FileContextMenuPlanItem(.tags),
            FileContextMenuPlanItem(.separator),
            FileContextMenuPlanItem(.showViewOptions),
            FileContextMenuPlanItem(.separator)
        ]
        if containsZip {
            items.append(FileContextMenuPlanItem(.extractZip))
        }
        if containsCloudItem {
            items.append(FileContextMenuPlanItem(.cloudDownload))
        }
        items.append(contentsOf: [
            FileContextMenuPlanItem(.copyPath),
            FileContextMenuPlanItem(.revealInFinder)
        ])
        return FileContextMenuPlan(items: items)
    }
}

private final class ThumbnailCellView: NSTableCellView {
    var representedFileURL: URL?
}

private final class FileThumbnailProvider {
    static let shared = FileThumbnailProvider()

    private let cache = NSCache<NSString, NSImage>()

    func thumbnail(for item: FileItem, size: CGSize, completion: @escaping (NSImage?) -> Void) {
        let modified = item.modifiedDate?.timeIntervalSince1970 ?? 0
        let cacheKey = "\(item.url.standardizedFileURL.path)|\(modified)" as NSString

        if let cached = cache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: size,
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: [.thumbnail, .lowQualityThumbnail]
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            let image = representation?.nsImage
            if let image {
                self?.cache.setObject(image, forKey: cacheKey)
            }
            DispatchQueue.main.async {
                completion(image)
            }
        }
    }
}

private final class FileIconCollectionItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("FileIconCollectionItem")

    private var representedFileURL: URL?

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.22).cgColor
                : NSColor.clear.cgColor
        }
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.cornerRadius = 7

        let preview = NSImageView()
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.imageScaling = .scaleProportionallyDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 4
        preview.layer?.masksToBounds = true
        root.addSubview(preview)
        imageView = preview

        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 2
        label.font = .systemFont(ofSize: 12)
        root.addSubview(label)
        textField = label

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: root.topAnchor, constant: 6),
            preview.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            preview.widthAnchor.constraint(equalToConstant: 66),
            preview.heightAnchor.constraint(equalToConstant: 66),

            label.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -4),
            label.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -4)
        ])

        view = root
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        representedFileURL = nil
        imageView?.image = nil
        imageView?.imageFrameStyle = .none
        textField?.stringValue = ""
    }

    func configure(with item: FileItem) {
        representedFileURL = item.url.standardizedFileURL
        textField?.stringValue = item.name
        imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
        imageView?.imageFrameStyle = .none

        guard !item.isDirectory else { return }

        FileThumbnailProvider.shared.thumbnail(
            for: item,
            size: NSSize(width: 132, height: 132)
        ) { [weak self] image in
            guard let self,
                  representedFileURL == item.url.standardizedFileURL,
                  let image else {
                return
            }
            imageView?.image = image
            imageView?.imageFrameStyle = .photo
        }
    }
}

private final class FinderCollectionView: NSCollectionView {
    var onActivate: (() -> Void)?
    var onDoubleClick: ((IndexPath) -> Void)?
    var onContextClick: ((NSEvent) -> Void)?
    var onReturn: (() -> Void)?
    var onDelete: (() -> Void)?
    var onPreview: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        let point = convert(event.locationInWindow, from: nil)
        let clickedIndexPath = indexPathForItem(at: point)
        super.mouseDown(with: event)
        if event.clickCount == 2, let clickedIndexPath {
            onDoubleClick?(clickedIndexPath)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onActivate?()
        onContextClick?(event)
        super.rightMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 {
            onReturn?()
            return
        }
        if event.keyCode == 51, event.modifierFlags.contains(.command) {
            onDelete?()
            return
        }
        if event.keyCode == 49 {
            onPreview?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class FinderBrowser: NSBrowser {
    var onActivate: (() -> Void)?
    var onContextClick: (() -> Void)?
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?
    var onPreview: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onActivate?()
        onContextClick?()
        super.rightMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 {
            onOpen?()
            return
        }
        if event.keyCode == 51, event.modifierFlags.contains(.command) {
            onDelete?()
            return
        }
        if event.keyCode == 49 {
            onPreview?()
            return
        }
        super.keyDown(with: event)
    }
}

protocol FileTableViewControllerDelegate: AnyObject {
    func fileTableDidActivate(_ controller: FileTableViewController)
    func fileTable(_ controller: FileTableViewController, didOpen item: FileItem)
    func fileTable(
        _ controller: FileTableViewController,
        didReceive urls: [URL],
        at destination: URL,
        operation: FileTransferOperation
    )
    func fileTableDidRequestRename(_ controller: FileTableViewController)
    func fileTableDidRequestBatchRename(_ controller: FileTableViewController)
    func fileTableDidRequestCreateZip(_ controller: FileTableViewController)
    func fileTableDidRequestExtractZip(_ controller: FileTableViewController)
    func fileTableDidRequestCloudDownload(_ controller: FileTableViewController)
    func fileTableDidRequestTrash(_ controller: FileTableViewController)
    func fileTableDidRequestPreview(_ controller: FileTableViewController)
    func fileTableDidRequestCopy(_ controller: FileTableViewController)
    func fileTableDidRequestPaste(_ controller: FileTableViewController)
    func fileTableDidRequestDuplicate(_ controller: FileTableViewController)
    func fileTableDidRequestInfo(_ controller: FileTableViewController)
    func fileTableDidRequestCopyPath(_ controller: FileTableViewController)
    func fileTableDidRequestReveal(_ controller: FileTableViewController)
    func fileTable(
        _ controller: FileTableViewController,
        didRequestSortBy option: FileSortOption,
        ascending: Bool
    )
    func fileTable(
        _ controller: FileTableViewController,
        didRequestViewMode mode: FileViewMode
    )
    func fileTableDidRequestNewFolder(_ controller: FileTableViewController)
    func fileTableDidRequestFolderWithSelection(_ controller: FileTableViewController)
    func fileTable(
        _ controller: FileTableViewController,
        didRequestOpenWith applicationURL: URL
    )
    func fileTableDidRequestChooseApplication(_ controller: FileTableViewController)
    func fileTableDidRequestAlias(_ controller: FileTableViewController)
    func fileTableDidRequestShowViewOptions(_ controller: FileTableViewController)
    func fileTableDidRequestToggleHiddenFiles(_ controller: FileTableViewController)
    func fileTable(
        _ controller: FileTableViewController,
        didRequestTag tag: FinderTag?
    )
}

final class FinderTableView: NSTableView {
    var onActivate: (() -> Void)?
    var onContextClick: ((NSEvent) -> Void)?
    var onReturn: (() -> Void)?
    var onDelete: (() -> Void)?
    var onPreview: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onActivate?()
        onContextClick?(event)
        super.rightMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 {
            onReturn?()
            return
        }
        if event.keyCode == 51, event.modifierFlags.contains(.command) {
            onDelete?()
            return
        }
        if event.keyCode == 49 {
            onPreview?()
            return
        }
        super.keyDown(with: event)
    }
}

final class FileTableViewController: NSViewController {
    weak var delegate: FileTableViewControllerDelegate?

    private let scrollView = NSScrollView()
    private let iconScrollView = NSScrollView()
    private let browser = FinderBrowser()
    private let galleryContainer = NSView()
    private let galleryPreviewImage = NSImageView()
    private let galleryNameLabel = NSTextField(labelWithString: "")
    private let galleryInfoLabel = NSTextField(labelWithString: "")
    private let galleryScrollView = NSScrollView()
    private let galleryCollectionView = FinderCollectionView()
    private let contextMenu = NSMenu()
    private var sharingPicker: NSSharingServicePicker?
    let tableView = FinderTableView()
    private let collectionView = FinderCollectionView()
    private(set) var items: [FileItem] = []
    var currentDirectory: URL?
    private(set) var viewMode: FileViewMode = .list
    private var browserItemsCache: [URL: [FileItem]] = [:]
    private var galleryRepresentedURL: URL?
    private var comparisonStates: [String: FolderComparisonState] = [:]
    private var currentSortOption: FileSortOption = .name
    private var currentSortAscending = true
    private var currentlyShowsHiddenFiles = false
    private var isUpdatingSortDescriptors = false
    private var clipboardHasFilesOverrideForTesting: Bool?

    private enum Column {
        static let name = NSUserInterfaceItemIdentifier("name")
        static let size = NSUserInterfaceItemIdentifier("size")
        static let kind = NSUserInterfaceItemIdentifier("kind")
        static let modified = NSUserInterfaceItemIdentifier("modified")
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        addColumn(identifier: Column.name, title: "名稱", width: 235, minWidth: 140)
        addColumn(identifier: Column.size, title: "大小", width: 90, minWidth: 70)
        addColumn(identifier: Column.kind, title: "種類", width: 125, minWidth: 90)
        addColumn(identifier: Column.modified, title: "修改日期", width: 140, minWidth: 115)

        tableView.usesAlternatingRowBackgroundColors = true
        tableView.style = .plain
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.rowHeight = 30
        tableView.intercellSpacing = NSSize(width: 8, height: 0)
        tableView.focusRingType = .none
        tableView.gridStyleMask = []
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openDoubleClickedItem)
        tableView.registerForDraggedTypes([.fileURL])
        tableView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy], forLocal: false)
        tableView.onActivate = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidActivate(self)
        }
        tableView.onContextClick = { [weak self] event in
            self?.prepareTableSelectionForContextMenu(event)
        }
        tableView.onReturn = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidRequestRename(self)
        }
        tableView.onDelete = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidRequestTrash(self)
        }
        tableView.onPreview = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidRequestPreview(self)
        }

        contextMenu.autoenablesItems = false
        contextMenu.delegate = self
        tableView.menu = contextMenu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        let iconLayout = NSCollectionViewFlowLayout()
        iconLayout.itemSize = NSSize(width: 102, height: 106)
        iconLayout.sectionInset = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        iconLayout.minimumInteritemSpacing = 8
        iconLayout.minimumLineSpacing = 10

        collectionView.collectionViewLayout = iconLayout
        collectionView.backgroundColors = [.textBackgroundColor]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.register(
            FileIconCollectionItem.self,
            forItemWithIdentifier: FileIconCollectionItem.identifier
        )
        collectionView.registerForDraggedTypes([.fileURL])
        collectionView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        collectionView.setDraggingSourceOperationMask([.copy], forLocal: false)
        collectionView.onActivate = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidActivate(self)
        }
        collectionView.onContextClick = { [weak self] event in
            guard let self else { return }
            prepareCollectionSelectionForContextMenu(event, collectionView: collectionView)
        }
        collectionView.onDoubleClick = { [weak self] indexPath in
            guard let self, indexPath.item < self.items.count else { return }
            self.delegate?.fileTable(self, didOpen: self.items[indexPath.item])
        }
        collectionView.onReturn = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidRequestRename(self)
        }
        collectionView.onDelete = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidRequestTrash(self)
        }
        collectionView.onPreview = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidRequestPreview(self)
        }
        collectionView.menu = contextMenu

        iconScrollView.documentView = collectionView
        iconScrollView.hasVerticalScroller = true
        iconScrollView.hasHorizontalScroller = false
        iconScrollView.autohidesScrollers = true
        iconScrollView.isHidden = true
        iconScrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(iconScrollView)

        browser.delegate = self
        browser.target = self
        browser.action = #selector(browserSelectionChanged)
        browser.doubleAction = #selector(openBrowserSelection)
        browser.allowsMultipleSelection = true
        browser.allowsEmptySelection = true
        browser.allowsBranchSelection = true
        browser.hasHorizontalScroller = true
        browser.autohidesScroller = true
        browser.separatesColumns = true
        browser.minColumnWidth = 180
        browser.maxVisibleColumns = 4
        browser.menu = contextMenu
        browser.onActivate = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidActivate(self)
        }
        browser.onContextClick = { [weak self] in
            guard let self else { return }
            delegate?.fileTableDidActivate(self)
        }
        browser.onOpen = { [weak self] in
            self?.openBrowserSelection()
        }
        browser.onDelete = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidRequestTrash(self)
        }
        browser.onPreview = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidRequestPreview(self)
        }
        browser.isHidden = true
        browser.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(browser)

        galleryContainer.wantsLayer = true
        galleryContainer.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        galleryContainer.isHidden = true
        galleryContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(galleryContainer)

        galleryPreviewImage.imageScaling = .scaleProportionallyDown
        galleryPreviewImage.wantsLayer = true
        galleryPreviewImage.layer?.cornerRadius = 7
        galleryPreviewImage.layer?.masksToBounds = true
        galleryPreviewImage.translatesAutoresizingMaskIntoConstraints = false
        galleryContainer.addSubview(galleryPreviewImage)

        galleryNameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        galleryNameLabel.alignment = .center
        galleryNameLabel.lineBreakMode = .byTruncatingMiddle
        galleryNameLabel.translatesAutoresizingMaskIntoConstraints = false
        galleryContainer.addSubview(galleryNameLabel)

        galleryInfoLabel.font = .systemFont(ofSize: 11)
        galleryInfoLabel.textColor = .secondaryLabelColor
        galleryInfoLabel.alignment = .center
        galleryInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        galleryContainer.addSubview(galleryInfoLabel)

        let galleryLayout = NSCollectionViewFlowLayout()
        galleryLayout.itemSize = NSSize(width: 102, height: 106)
        galleryLayout.sectionInset = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        galleryLayout.minimumInteritemSpacing = 8
        galleryLayout.minimumLineSpacing = 8
        galleryLayout.scrollDirection = .horizontal

        galleryCollectionView.collectionViewLayout = galleryLayout
        galleryCollectionView.backgroundColors = [.controlBackgroundColor]
        galleryCollectionView.isSelectable = true
        galleryCollectionView.allowsMultipleSelection = true
        galleryCollectionView.delegate = self
        galleryCollectionView.dataSource = self
        galleryCollectionView.register(
            FileIconCollectionItem.self,
            forItemWithIdentifier: FileIconCollectionItem.identifier
        )
        galleryCollectionView.registerForDraggedTypes([.fileURL])
        galleryCollectionView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        galleryCollectionView.setDraggingSourceOperationMask([.copy], forLocal: false)
        galleryCollectionView.onActivate = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidActivate(self)
        }
        galleryCollectionView.onContextClick = { [weak self] event in
            guard let self else { return }
            prepareCollectionSelectionForContextMenu(event, collectionView: galleryCollectionView)
        }
        galleryCollectionView.onDoubleClick = { [weak self] indexPath in
            guard let self, indexPath.item < self.items.count else { return }
            self.delegate?.fileTable(self, didOpen: self.items[indexPath.item])
        }
        galleryCollectionView.onReturn = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidRequestRename(self)
        }
        galleryCollectionView.onDelete = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidRequestTrash(self)
        }
        galleryCollectionView.onPreview = { [weak self] in
            guard let self else { return }
            self.delegate?.fileTableDidRequestPreview(self)
        }
        galleryCollectionView.menu = contextMenu

        galleryScrollView.documentView = galleryCollectionView
        galleryScrollView.hasVerticalScroller = false
        galleryScrollView.hasHorizontalScroller = true
        galleryScrollView.autohidesScrollers = true
        galleryScrollView.translatesAutoresizingMaskIntoConstraints = false
        galleryContainer.addSubview(galleryScrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            iconScrollView.topAnchor.constraint(equalTo: root.topAnchor),
            iconScrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            iconScrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            iconScrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            browser.topAnchor.constraint(equalTo: root.topAnchor),
            browser.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            browser.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            browser.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            galleryContainer.topAnchor.constraint(equalTo: root.topAnchor),
            galleryContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            galleryContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            galleryContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            galleryPreviewImage.topAnchor.constraint(equalTo: galleryContainer.topAnchor, constant: 14),
            galleryPreviewImage.leadingAnchor.constraint(equalTo: galleryContainer.leadingAnchor, constant: 14),
            galleryPreviewImage.trailingAnchor.constraint(equalTo: galleryContainer.trailingAnchor, constant: -14),
            galleryPreviewImage.bottomAnchor.constraint(equalTo: galleryNameLabel.topAnchor, constant: -8),

            galleryNameLabel.leadingAnchor.constraint(equalTo: galleryContainer.leadingAnchor, constant: 12),
            galleryNameLabel.trailingAnchor.constraint(equalTo: galleryContainer.trailingAnchor, constant: -12),
            galleryNameLabel.bottomAnchor.constraint(equalTo: galleryInfoLabel.topAnchor, constant: -3),

            galleryInfoLabel.leadingAnchor.constraint(equalTo: galleryContainer.leadingAnchor, constant: 12),
            galleryInfoLabel.trailingAnchor.constraint(equalTo: galleryContainer.trailingAnchor, constant: -12),
            galleryInfoLabel.bottomAnchor.constraint(equalTo: galleryScrollView.topAnchor, constant: -8),

            galleryScrollView.leadingAnchor.constraint(equalTo: galleryContainer.leadingAnchor),
            galleryScrollView.trailingAnchor.constraint(equalTo: galleryContainer.trailingAnchor),
            galleryScrollView.bottomAnchor.constraint(equalTo: galleryContainer.bottomAnchor),
            galleryScrollView.heightAnchor.constraint(equalToConstant: 126)
        ])

        self.view = root
    }

    func reload(items: [FileItem], currentDirectory: URL) {
        let selected = Set(selectedURLs())
        self.items = items
        self.currentDirectory = currentDirectory
        tableView.reloadData()
        collectionView.reloadData()
        galleryCollectionView.reloadData()
        browserItemsCache.removeAll()
        browser.loadColumnZero()

        let indexes = IndexSet(items.indices.filter { selected.contains(items[$0].url) })
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        collectionView.selectionIndexPaths = Set(
            indexes.map { IndexPath(item: $0, section: 0) }
        )
        galleryCollectionView.selectionIndexPaths = Set(
            indexes.map { IndexPath(item: $0, section: 0) }
        )
        if galleryCollectionView.selectionIndexPaths.isEmpty, !items.isEmpty {
            galleryCollectionView.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
        }
        updateGalleryPreview()
    }

    func setDisplayOptions(
        sortOption: FileSortOption,
        ascending: Bool,
        showHiddenFiles: Bool
    ) {
        currentSortOption = sortOption
        currentSortAscending = ascending
        currentlyShowsHiddenFiles = showHiddenFiles

        guard let column = tableColumn(for: sortOption) else { return }
        let descriptor = NSSortDescriptor(
            key: column.identifier.rawValue,
            ascending: ascending
        )
        isUpdatingSortDescriptors = true
        tableView.sortDescriptors = [descriptor]
        tableView.highlightedTableColumn = column
        isUpdatingSortDescriptors = false
    }

    func showComparison(_ states: [String: FolderComparisonState]) {
        comparisonStates = states
        tableView.reloadData()
        collectionView.reloadData()
        galleryCollectionView.reloadData()
    }

    func clearComparison() {
        showComparison([:])
    }

    func setViewMode(_ mode: FileViewMode) {
        guard viewMode != mode else { return }
        let selected = Set(selectedURLs())
        viewMode = mode
        scrollView.isHidden = mode != .list
        iconScrollView.isHidden = mode != .icons
        browser.isHidden = mode != .columns
        galleryContainer.isHidden = mode != .gallery

        let indexes = items.indices.filter { selected.contains(items[$0].url) }
        tableView.selectRowIndexes(IndexSet(indexes), byExtendingSelection: false)
        collectionView.selectionIndexPaths = Set(
            indexes.map { IndexPath(item: $0, section: 0) }
        )
        galleryCollectionView.selectionIndexPaths = Set(
            indexes.map { IndexPath(item: $0, section: 0) }
        )
        if mode == .columns {
            browser.loadColumnZero()
        } else if mode == .gallery {
            if galleryCollectionView.selectionIndexPaths.isEmpty, !items.isEmpty {
                galleryCollectionView.selectionIndexPaths = [IndexPath(item: 0, section: 0)]
            }
            updateGalleryPreview()
        }
    }

    func selectedURLs() -> [URL] {
        if viewMode == .columns {
            return browser.selectionIndexPaths.compactMap { indexPath in
                let item = browser.item(at: indexPath as IndexPath)
                return (item as? NSURL) as URL?
            }
        }
        return selectedIndexes().compactMap { index -> URL? in
            guard index >= 0, index < items.count else { return nil }
            return items[index].url
        }
    }

    func selectedItems() -> [FileItem] {
        if viewMode == .columns {
            return selectedURLs().compactMap { FileItem.loadItem(at: $0) }
        }
        return selectedIndexes().compactMap { index -> FileItem? in
            guard index >= 0, index < items.count else { return nil }
            return items[index]
        }
    }

    private func selectedIndexes() -> [Int] {
        switch viewMode {
        case .list:
            return Array(tableView.selectedRowIndexes)
        case .icons:
            return collectionView.selectionIndexPaths.map(\.item).sorted()
        case .columns:
            return []
        case .gallery:
            return galleryCollectionView.selectionIndexPaths.map(\.item).sorted()
        }
    }

    func selectListItemForContextMenu(at row: Int) {
        guard row >= 0, row < items.count else {
            tableView.deselectAll(nil)
            return
        }
        guard !tableView.selectedRowIndexes.contains(row) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    func contextMenuTitlesForTesting(clipboardHasFiles: Bool) -> [String] {
        let menu = contextMenuForTesting(clipboardHasFiles: clipboardHasFiles)
        return menu.items.map { item in
            item.isSeparatorItem ? "—" : item.title
        }
    }

    func contextMenuItemIsEnabledForTesting(
        title: String,
        clipboardHasFiles: Bool
    ) -> Bool? {
        contextMenuForTesting(clipboardHasFiles: clipboardHasFiles)
            .items
            .first(where: { $0.title == title })?
            .isEnabled
    }

    private func contextMenuForTesting(clipboardHasFiles: Bool) -> NSMenu {
        clipboardHasFilesOverrideForTesting = clipboardHasFiles
        defer { clipboardHasFilesOverrideForTesting = nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menuNeedsUpdate(menu)
        return menu
    }

    private func prepareTableSelectionForContextMenu(_ event: NSEvent) {
        let point = tableView.convert(event.locationInWindow, from: nil)
        selectListItemForContextMenu(at: tableView.row(at: point))
    }

    private func prepareBrowserSelectionForContextMenuIfNeeded() {
        let column = browser.clickedColumn
        guard column >= 0 else { return }

        let row = browser.clickedRow
        guard row >= 0 else {
            browser.selectionIndexPaths = []
            return
        }
        let selectedRows = browser.selectedRowIndexes(inColumn: column) ?? []
        guard !selectedRows.contains(row) else { return }
        browser.selectRow(row, inColumn: column)
    }

    private func prepareCollectionSelectionForContextMenu(
        _ event: NSEvent,
        collectionView: NSCollectionView
    ) {
        let point = collectionView.convert(event.locationInWindow, from: nil)
        guard let indexPath = collectionView.indexPathForItem(at: point) else {
            collectionView.selectionIndexPaths = []
            return
        }
        guard !collectionView.selectionIndexPaths.contains(indexPath) else { return }
        collectionView.selectionIndexPaths = [indexPath]
    }

    private func updateGalleryPreview() {
        guard let index = galleryCollectionView.selectionIndexPaths.sorted(by: {
            $0.item < $1.item
        }).first?.item,
        index >= 0,
        index < items.count else {
            galleryRepresentedURL = nil
            galleryPreviewImage.image = nil
            galleryNameLabel.stringValue = ""
            galleryInfoLabel.stringValue = ""
            return
        }

        let item = items[index]
        galleryRepresentedURL = item.url.standardizedFileURL
        galleryPreviewImage.image = NSWorkspace.shared.icon(forFile: item.url.path)
        galleryNameLabel.stringValue = item.name
        galleryInfoLabel.stringValue = "\(item.kind) · \(FileFormatting.size(for: item)) · \(FileFormatting.date(item.modifiedDate))"

        guard !item.isDirectory else { return }
        FileThumbnailProvider.shared.thumbnail(
            for: item,
            size: NSSize(width: 900, height: 650)
        ) { [weak self] image in
            guard let self,
                  galleryRepresentedURL == item.url.standardizedFileURL,
                  let image else {
                return
            }
            galleryPreviewImage.image = image
        }
    }

    @objc private func openDoubleClickedItem() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        delegate?.fileTable(self, didOpen: items[row])
    }

    @objc private func menuOpen() {
        selectedItems().forEach { delegate?.fileTable(self, didOpen: $0) }
    }

    @objc private func menuRename() {
        delegate?.fileTableDidRequestRename(self)
    }

    @objc private func menuBatchRename() {
        delegate?.fileTableDidRequestBatchRename(self)
    }

    @objc private func menuCreateZip() {
        delegate?.fileTableDidRequestCreateZip(self)
    }

    @objc private func menuExtractZip() {
        delegate?.fileTableDidRequestExtractZip(self)
    }

    @objc private func menuCloudDownload() {
        delegate?.fileTableDidRequestCloudDownload(self)
    }

    @objc private func menuTrash() {
        delegate?.fileTableDidRequestTrash(self)
    }

    @objc private func menuPreview() {
        delegate?.fileTableDidRequestPreview(self)
    }

    @objc private func menuCopy() {
        delegate?.fileTableDidRequestCopy(self)
    }

    @objc private func menuPaste() {
        delegate?.fileTableDidRequestPaste(self)
    }

    @objc private func menuDuplicate() {
        delegate?.fileTableDidRequestDuplicate(self)
    }

    @objc private func menuInfo() {
        delegate?.fileTableDidRequestInfo(self)
    }

    @objc private func menuCopyPath() {
        delegate?.fileTableDidRequestCopyPath(self)
    }

    @objc private func menuReveal() {
        delegate?.fileTableDidRequestReveal(self)
    }

    @objc private func menuNewFolder() {
        delegate?.fileTableDidRequestNewFolder(self)
    }

    @objc private func menuFolderWithSelection() {
        delegate?.fileTableDidRequestFolderWithSelection(self)
    }

    @objc private func menuOpenWith(_ sender: NSMenuItem) {
        guard let applicationURL = sender.representedObject as? URL else { return }
        delegate?.fileTable(self, didRequestOpenWith: applicationURL)
    }

    @objc private func menuChooseApplication() {
        delegate?.fileTableDidRequestChooseApplication(self)
    }

    @objc private func menuAlias() {
        delegate?.fileTableDidRequestAlias(self)
    }

    @objc private func menuShowViewOptions() {
        delegate?.fileTableDidRequestShowViewOptions(self)
    }

    @objc private func menuToggleHiddenFiles() {
        delegate?.fileTableDidRequestToggleHiddenFiles(self)
    }

    @objc private func menuViewMode(_ sender: NSMenuItem) {
        guard let mode = FileViewMode(rawValue: sender.tag) else { return }
        delegate?.fileTable(self, didRequestViewMode: mode)
    }

    @objc private func menuSortOption(_ sender: NSMenuItem) {
        guard let option = FileSortOption(rawValue: sender.tag) else { return }
        delegate?.fileTable(
            self,
            didRequestSortBy: option,
            ascending: currentSortAscending
        )
    }

    @objc private func menuSortAscending() {
        delegate?.fileTable(
            self,
            didRequestSortBy: currentSortOption,
            ascending: true
        )
    }

    @objc private func menuSortDescending() {
        delegate?.fileTable(
            self,
            didRequestSortBy: currentSortOption,
            ascending: false
        )
    }

    @objc private func menuApplyTag(_ sender: NSMenuItem) {
        guard let tag = FinderTag.allCases.first(where: {
            $0.colorNumber == sender.tag
        }) else {
            return
        }
        delegate?.fileTable(self, didRequestTag: tag)
    }

    @objc private func menuClearTags() {
        delegate?.fileTable(self, didRequestTag: nil)
    }

    @objc private func menuShare() {
        let urls = selectedURLs()
        guard !urls.isEmpty else { return }

        let picker = NSSharingServicePicker(items: urls)
        sharingPicker = picker
        let anchorView = activeContentView()
        let windowPoint = view.window?.mouseLocationOutsideOfEventStream
            ?? NSPoint(x: anchorView.bounds.midX, y: anchorView.bounds.midY)
        let anchorPoint = anchorView.convert(windowPoint, from: nil)
        picker.show(
            relativeTo: NSRect(origin: anchorPoint, size: NSSize(width: 1, height: 1)),
            of: anchorView,
            preferredEdge: .minY
        )
    }

    private func activeContentView() -> NSView {
        switch viewMode {
        case .list:
            return tableView
        case .icons:
            return collectionView
        case .columns:
            return browser
        case .gallery:
            return galleryCollectionView
        }
    }

    @objc private func browserSelectionChanged() {
        delegate?.fileTableDidActivate(self)
    }

    @objc private func openBrowserSelection() {
        selectedItems().forEach { delegate?.fileTable(self, didOpen: $0) }
    }

    private func addColumn(
        identifier: NSUserInterfaceItemIdentifier,
        title: String,
        width: CGFloat,
        minWidth: CGFloat
    ) {
        let column = NSTableColumn(identifier: identifier)
        column.title = title
        column.width = width
        column.minWidth = minWidth
        column.resizingMask = .userResizingMask
        column.sortDescriptorPrototype = NSSortDescriptor(
            key: identifier.rawValue,
            ascending: true
        )
        tableView.addTableColumn(column)
    }

    private func tableColumn(for option: FileSortOption) -> NSTableColumn? {
        let identifier: NSUserInterfaceItemIdentifier
        switch option {
        case .name: identifier = Column.name
        case .size: identifier = Column.size
        case .modified: identifier = Column.modified
        case .kind: identifier = Column.kind
        }
        return tableView.tableColumn(withIdentifier: identifier)
    }

    private func sortOption(for key: String) -> FileSortOption? {
        switch NSUserInterfaceItemIdentifier(key) {
        case Column.name: return .name
        case Column.size: return .size
        case Column.modified: return .modified
        case Column.kind: return .kind
        default: return nil
        }
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

    private func destination(for proposedRow: Int) -> URL? {
        if proposedRow >= 0,
           proposedRow < items.count,
           items[proposedRow].shouldOpenAsFolder {
            return items[proposedRow].url
        }
        return currentDirectory
    }

    private func plainCell(identifier: NSUserInterfaceItemIdentifier, text: String) -> NSTableCellView {
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
            reused.textField?.stringValue = text
            return reused
        }

        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 12)
        cell.textField = label
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -3),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func nameCell(for item: FileItem) -> NSTableCellView {
        let identifier = NSUserInterfaceItemIdentifier("NameCell")
        let cell: ThumbnailCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? ThumbnailCellView {
            cell = reused
        } else {
            cell = ThumbnailCellView()
            cell.identifier = identifier

            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.imageScaling = .scaleProportionallyDown
            icon.wantsLayer = true
            icon.layer?.cornerRadius = 3
            icon.layer?.masksToBounds = true
            cell.imageView = icon
            cell.addSubview(icon)

            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            label.font = .systemFont(ofSize: 12)
            cell.textField = label
            cell.addSubview(label)

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 24),
                icon.heightAnchor.constraint(equalToConstant: 24),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -3),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }

        cell.representedFileURL = item.url.standardizedFileURL
        cell.textField?.stringValue = item.name
        switch comparisonStates[item.name.lowercased()] {
        case .onlyHere:
            cell.textField?.textColor = .systemBlue
            cell.textField?.toolTip = "只在呢邊"
        case .different:
            cell.textField?.textColor = .systemOrange
            cell.textField?.toolTip = "兩邊版本唔同"
        case .same:
            cell.textField?.textColor = .secondaryLabelColor
            cell.textField?.toolTip = "兩邊一樣"
        case nil:
            cell.textField?.textColor = .labelColor
            cell.textField?.toolTip = nil
        }
        cell.imageView?.image = NSWorkspace.shared.icon(forFile: item.url.path)
        cell.imageView?.imageFrameStyle = .none

        guard !item.isDirectory else { return cell }

        FileThumbnailProvider.shared.thumbnail(
            for: item,
            size: NSSize(width: 48, height: 48)
        ) { [weak cell] image in
            guard let cell,
                  cell.representedFileURL == item.url.standardizedFileURL,
                  let image else {
                return
            }
            cell.imageView?.image = image
            cell.imageView?.imageFrameStyle = .photo
        }
        return cell
    }
}

extension FileTableViewController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier else { return nil }
        let item = items[row]
        switch identifier {
        case Column.name:
            return nameCell(for: item)
        case Column.size:
            return plainCell(identifier: NSUserInterfaceItemIdentifier("SizeCell"), text: FileFormatting.size(for: item))
        case Column.kind:
            let cloud = item.cloudAvailability.title
            let kindText = cloud.isEmpty ? item.kind : "\(item.kind) · \(cloud)"
            return plainCell(identifier: NSUserInterfaceItemIdentifier("KindCell"), text: kindText)
        case Column.modified:
            return plainCell(identifier: NSUserInterfaceItemIdentifier("DateCell"), text: FileFormatting.date(item.modifiedDate))
        default:
            return nil
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        delegate?.fileTableDidActivate(self)
    }

    func tableView(
        _ tableView: NSTableView,
        sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]
    ) {
        guard !isUpdatingSortDescriptors,
              let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key,
              let option = sortOption(for: key) else {
            return
        }
        currentSortOption = option
        currentSortAscending = descriptor.ascending
        delegate?.fileTable(
            self,
            didRequestSortBy: option,
            ascending: descriptor.ascending
        )
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row >= 0, row < items.count else { return nil }
        return items[row].url as NSURL
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        guard !draggedURLs(from: info).isEmpty, destination(for: row) != nil else {
            return []
        }
        if row >= 0, row < items.count, items[row].shouldOpenAsFolder {
            tableView.setDropRow(row, dropOperation: .on)
        } else {
            tableView.setDropRow(-1, dropOperation: .on)
        }
        return dragOperation() == .copy ? .copy : .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let destination = destination(for: row) else { return false }
        let urls = draggedURLs(from: info)
        guard !urls.isEmpty else { return false }
        delegate?.fileTable(
            self,
            didReceive: urls,
            at: destination,
            operation: dragOperation()
        )
        return true
    }
}

extension FileTableViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let item = collectionView.makeItem(
            withIdentifier: FileIconCollectionItem.identifier,
            for: indexPath
        )
        guard let iconItem = item as? FileIconCollectionItem,
              indexPath.item < items.count else {
            return item
        }
        iconItem.configure(with: items[indexPath.item])
        return iconItem
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        didSelectItemsAt indexPaths: Set<IndexPath>
    ) {
        delegate?.fileTableDidActivate(self)
        if collectionView === galleryCollectionView {
            updateGalleryPreview()
        }
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        pasteboardWriterForItemAt indexPath: IndexPath
    ) -> NSPasteboardWriting? {
        guard indexPath.item < items.count else { return nil }
        return items[indexPath.item].url as NSURL
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        validateDrop draggingInfo: NSDraggingInfo,
        proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        let indexPath = proposedIndexPath.pointee as IndexPath
        let row = indexPath.item
        guard !draggedURLs(from: draggingInfo).isEmpty,
              destination(for: row) != nil else {
            return []
        }
        dropOperation.pointee = row < items.count && items[row].shouldOpenAsFolder ? .on : .before
        return dragOperation() == .copy ? .copy : .move
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        acceptDrop draggingInfo: NSDraggingInfo,
        indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        guard let destination = destination(for: indexPath.item) else { return false }
        let urls = draggedURLs(from: draggingInfo)
        guard !urls.isEmpty else { return false }
        delegate?.fileTable(
            self,
            didReceive: urls,
            at: destination,
            operation: dragOperation()
        )
        return true
    }
}

extension FileTableViewController: NSBrowserDelegate {
    func rootItem(for browser: NSBrowser) -> Any? {
        currentDirectory as NSURL?
    }

    func browser(_ browser: NSBrowser, numberOfChildrenOfItem item: Any?) -> Int {
        guard let directory = (item as? NSURL) as URL? else { return 0 }
        return browserItems(in: directory).count
    }

    func browser(_ browser: NSBrowser, child index: Int, ofItem item: Any?) -> Any {
        guard let directory = (item as? NSURL) as URL? else {
            return NSURL(fileURLWithPath: "/")
        }
        let children = browserItems(in: directory)
        guard index >= 0, index < children.count else {
            return NSURL(fileURLWithPath: "/")
        }
        return children[index].url as NSURL
    }

    func browser(_ browser: NSBrowser, isLeafItem item: Any?) -> Bool {
        guard let url = (item as? NSURL) as URL?,
              let fileItem = FileItem.loadItem(at: url) else {
            return true
        }
        return !fileItem.shouldOpenAsFolder
    }

    func browser(_ browser: NSBrowser, objectValueForItem item: Any?) -> Any? {
        guard let url = (item as? NSURL) as URL? else { return nil }
        return FileManager.default.displayName(atPath: url.path)
    }

    func browser(
        _ sender: NSBrowser,
        willDisplayCell cell: Any,
        atRow row: Int,
        column: Int
    ) {
        guard let browserCell = cell as? NSBrowserCell,
              let url = (sender.item(atRow: row, inColumn: column) as? NSURL) as URL? else {
            return
        }
        browserCell.image = NSWorkspace.shared.icon(forFile: url.path)
        browserCell.isLeaf = !(FileItem.loadItem(at: url)?.shouldOpenAsFolder == true)
    }

    func browser(_ sender: NSBrowser, titleOfColumn column: Int) -> String? {
        guard let parent = (sender.parentForItems(inColumn: column) as? NSURL) as URL? else {
            return currentDirectory?.lastPathComponent
        }
        return FileManager.default.displayName(atPath: parent.path)
    }

    private func browserItems(in directory: URL) -> [FileItem] {
        let standardized = directory.standardizedFileURL
        if standardized == currentDirectory?.standardizedFileURL {
            return items
        }
        if let cached = browserItemsCache[standardized] {
            return cached
        }
        let loaded = (try? FileItem.load(from: standardized)) ?? []
        browserItemsCache[standardized] = loaded
        return loaded
    }
}

extension FileTableViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        prepareBrowserSelectionForContextMenuIfNeeded()
        let selected = selectedItems()
        let containsZip = selected.contains {
            $0.url.pathExtension.lowercased() == "zip"
        }
        let containsCloudItem = selected.contains {
            $0.cloudAvailability == .onlineOnly || $0.cloudAvailability == .downloading
        }
        let plan = FileContextMenuPlan.make(
            selectionCount: selected.count,
            containsZip: containsZip,
            containsCloudItem: containsCloudItem,
            clipboardHasFiles: clipboardHasFilesOverrideForTesting
                ?? clipboardContainsFileURLs()
        )

        for planItem in plan.items {
            switch planItem.command {
            case .separator:
                menu.addItem(.separator())

            case .newFolder:
                addMenuItem(
                    to: menu,
                    title: "新增資料夾",
                    action: #selector(menuNewFolder),
                    keyEquivalent: "n",
                    modifiers: [.command, .shift]
                )

            case .paste:
                addMenuItem(
                    to: menu,
                    title: "貼上項目",
                    action: #selector(menuPaste),
                    keyEquivalent: "v",
                    modifiers: [.command],
                    isEnabled: planItem.isEnabled
                )

            case .viewMode:
                addSubmenu(
                    makeViewModeMenu(),
                    to: menu,
                    title: "顯示方式"
                )

            case .sort:
                addSubmenu(
                    makeSortMenu(),
                    to: menu,
                    title: "排列方式"
                )

            case .showViewOptions:
                addMenuItem(
                    to: menu,
                    title: "顯示選項…",
                    action: #selector(menuShowViewOptions),
                    keyEquivalent: "j",
                    modifiers: [.command]
                )

            case .toggleHiddenFiles:
                addMenuItem(
                    to: menu,
                    title: currentlyShowsHiddenFiles ? "隱藏隱藏檔案" : "顯示隱藏檔案",
                    action: #selector(menuToggleHiddenFiles),
                    keyEquivalent: ".",
                    modifiers: [.command, .shift]
                )

            case .folderWithSelection:
                addMenuItem(
                    to: menu,
                    title: "新增包含所選 \(selected.count) 個項目的資料夾",
                    action: #selector(menuFolderWithSelection),
                    keyEquivalent: "n",
                    modifiers: [.command, .control]
                )

            case .open:
                let title = selected.count == 1 ? "開啟" : "開啟 \(selected.count) 個項目"
                addMenuItem(
                    to: menu,
                    title: title,
                    action: #selector(menuOpen),
                    keyEquivalent: "o",
                    modifiers: [.command]
                )

            case .openWith:
                addSubmenu(
                    makeOpenWithMenu(for: selected.map(\.url)),
                    to: menu,
                    title: "打開檔案的應用程式"
                )

            case .trash:
                addMenuItem(
                    to: menu,
                    title: "丟到垃圾桶",
                    action: #selector(menuTrash),
                    keyEquivalent: "\u{8}",
                    modifiers: [.command]
                )

            case .info:
                addMenuItem(
                    to: menu,
                    title: "取得資料",
                    action: #selector(menuInfo),
                    keyEquivalent: "i",
                    modifiers: [.command]
                )

            case .rename:
                addMenuItem(
                    to: menu,
                    title: selected.count == 1
                        ? "重新命名…"
                        : "重新命名 \(selected.count) 個項目…",
                    action: selected.count == 1
                        ? #selector(menuRename)
                        : #selector(menuBatchRename),
                    keyEquivalent: "\r",
                    modifiers: []
                )

            case .compress:
                addMenuItem(
                    to: menu,
                    title: selected.count == 1 ? "壓縮" : "壓縮 \(selected.count) 個項目",
                    action: #selector(menuCreateZip)
                )

            case .duplicate:
                addMenuItem(
                    to: menu,
                    title: selected.count == 1 ? "複製" : "複製 \(selected.count) 個項目",
                    action: #selector(menuDuplicate),
                    keyEquivalent: "d",
                    modifiers: [.command]
                )

            case .alias:
                addMenuItem(
                    to: menu,
                    title: selected.count == 1 ? "製作替身" : "製作 \(selected.count) 個替身",
                    action: #selector(menuAlias),
                    keyEquivalent: "l",
                    modifiers: [.command]
                )

            case .preview:
                addMenuItem(
                    to: menu,
                    title: selected.count == 1 ? "快速查看" : "快速查看 \(selected.count) 個項目",
                    action: #selector(menuPreview),
                    keyEquivalent: " ",
                    modifiers: []
                )

            case .copy:
                addMenuItem(
                    to: menu,
                    title: selected.count == 1 ? "拷貝" : "拷貝 \(selected.count) 個項目",
                    action: #selector(menuCopy),
                    keyEquivalent: "c",
                    modifiers: [.command]
                )

            case .share:
                addMenuItem(
                    to: menu,
                    title: "分享…",
                    action: #selector(menuShare)
                )

            case .tags:
                addSubmenu(
                    makeTagsMenu(),
                    to: menu,
                    title: "標籤"
                )

            case .extractZip:
                addMenuItem(
                    to: menu,
                    title: "解壓 ZIP",
                    action: #selector(menuExtractZip)
                )

            case .cloudDownload:
                addMenuItem(
                    to: menu,
                    title: "立即下載雲端檔案",
                    action: #selector(menuCloudDownload)
                )

            case .copyPath:
                addMenuItem(
                    to: menu,
                    title: "複製路徑",
                    action: #selector(menuCopyPath),
                    keyEquivalent: "c",
                    modifiers: [.command, .option]
                )

            case .revealInFinder:
                addMenuItem(
                    to: menu,
                    title: "在 Apple Finder 顯示",
                    action: #selector(menuReveal)
                )
            }
        }
    }

    @discardableResult
    private func addMenuItem(
        to menu: NSMenu,
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = menu.addItem(
            withTitle: title,
            action: action,
            keyEquivalent: keyEquivalent
        )
        item.target = self
        item.isEnabled = isEnabled
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    private func addSubmenu(_ submenu: NSMenu, to menu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        menu.addItem(item)
    }

    private func clipboardContainsFileURLs() -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        return NSPasteboard.general.canReadObject(
            forClasses: [NSURL.self],
            options: options
        )
    }

    private func makeOpenWithMenu(for urls: [URL]) -> NSMenu {
        let menu = NSMenu(title: "打開檔案的應用程式")
        guard let firstURL = urls.first else { return menu }

        let workspace = NSWorkspace.shared
        var applicationURLs = workspace.urlsForApplications(toOpen: firstURL)
        if urls.count > 1 {
            var commonPaths = Set(applicationURLs.map(\.standardizedFileURL.path))
            for url in urls.dropFirst() {
                commonPaths.formIntersection(
                    workspace.urlsForApplications(toOpen: url).map(\.standardizedFileURL.path)
                )
            }
            applicationURLs = applicationURLs.filter {
                commonPaths.contains($0.standardizedFileURL.path)
            }
        }

        var seenPaths = Set<String>()
        applicationURLs = applicationURLs
            .filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
            .sorted {
                FileManager.default.displayName(atPath: $0.path)
                    .localizedStandardCompare(
                        FileManager.default.displayName(atPath: $1.path)
                    ) == .orderedAscending
            }

        let defaultApplication = workspace.urlForApplication(toOpen: firstURL)?
            .standardizedFileURL
        if applicationURLs.isEmpty {
            let empty = NSMenuItem(
                title: "冇合適應用程式",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for applicationURL in applicationURLs {
                let item = menu.addItem(
                    withTitle: FileManager.default.displayName(atPath: applicationURL.path),
                    action: #selector(menuOpenWith(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = applicationURL
                item.image = workspace.icon(forFile: applicationURL.path)
                item.image?.size = NSSize(width: 16, height: 16)
                if applicationURL.standardizedFileURL == defaultApplication {
                    item.state = .on
                }
            }
        }

        menu.addItem(.separator())
        let other = menu.addItem(
            withTitle: "其他…",
            action: #selector(menuChooseApplication),
            keyEquivalent: ""
        )
        other.target = self
        return menu
    }

    private func makeViewModeMenu() -> NSMenu {
        let menu = NSMenu(title: "顯示方式")
        for mode in FileViewMode.allCases {
            let keyEquivalent: String
            switch mode {
            case .icons: keyEquivalent = "1"
            case .list: keyEquivalent = "2"
            case .columns: keyEquivalent = "3"
            case .gallery: keyEquivalent = "4"
            }
            let item = menu.addItem(
                withTitle: mode.title,
                action: #selector(menuViewMode(_:)),
                keyEquivalent: keyEquivalent
            )
            item.target = self
            item.tag = mode.rawValue
            item.keyEquivalentModifierMask = [.command]
            item.state = mode == viewMode ? .on : .off
        }
        return menu
    }

    private func makeSortMenu() -> NSMenu {
        let menu = NSMenu(title: "排列方式")
        for option in FileSortOption.allCases {
            let item = menu.addItem(
                withTitle: option.title,
                action: #selector(menuSortOption(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = option.rawValue
            item.state = option == currentSortOption ? .on : .off
        }

        menu.addItem(.separator())
        let ascending = menu.addItem(
            withTitle: "由細至大",
            action: #selector(menuSortAscending),
            keyEquivalent: ""
        )
        ascending.target = self
        ascending.state = currentSortAscending ? .on : .off

        let descending = menu.addItem(
            withTitle: "由大至細",
            action: #selector(menuSortDescending),
            keyEquivalent: ""
        )
        descending.target = self
        descending.state = currentSortAscending ? .off : .on
        return menu
    }

    private func makeTagsMenu() -> NSMenu {
        let menu = NSMenu(title: "標籤")
        for tag in FinderTag.allCases {
            let item = menu.addItem(
                withTitle: tag.title,
                action: #selector(menuApplyTag(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = tag.colorNumber
            item.image = tagImage(color: tag.color)
        }
        menu.addItem(.separator())
        let clear = menu.addItem(
            withTitle: "清除標籤",
            action: #selector(menuClearTags),
            keyEquivalent: ""
        )
        clear.target = self
        return menu
    }

    private func tagImage(color: NSColor) -> NSImage {
        guard let image = NSImage(
            systemSymbolName: "circle.fill",
            accessibilityDescription: "標籤"
        ) else {
            return NSImage(size: NSSize(width: 12, height: 12))
        }
        let palette = NSImage.SymbolConfiguration(paletteColors: [color])
        let size = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        return image.withSymbolConfiguration(palette.applying(size)) ?? image
    }
}
