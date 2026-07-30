import AppKit
import QuickLookThumbnailing

enum FileViewMode: Int {
    case list
    case icons
    case columns
    case gallery
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
    var onOpen: (() -> Void)?
    var onDelete: (() -> Void)?
    var onPreview: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        super.mouseDown(with: event)
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
}

final class FinderTableView: NSTableView {
    var onActivate: (() -> Void)?
    var onReturn: (() -> Void)?
    var onDelete: (() -> Void)?
    var onPreview: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        super.mouseDown(with: event)
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
    let tableView = FinderTableView()
    private let collectionView = FinderCollectionView()
    private(set) var items: [FileItem] = []
    var currentDirectory: URL?
    private(set) var viewMode: FileViewMode = .list
    private var browserItemsCache: [URL: [FileItem]] = [:]
    private var galleryRepresentedURL: URL?
    private var comparisonStates: [String: FolderComparisonState] = [:]

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
        tableView.addTableColumn(column)
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
        let hasSelection = !selectedItems().isEmpty
        let singleSelection = selectedItems().count == 1

        let open = menu.addItem(
            withTitle: "開啟",
            action: #selector(menuOpen),
            keyEquivalent: ""
        )
        open.target = self
        open.isEnabled = hasSelection

        let preview = menu.addItem(
            withTitle: "快速預覽",
            action: #selector(menuPreview),
            keyEquivalent: ""
        )
        preview.target = self
        preview.isEnabled = hasSelection

        menu.addItem(.separator())
        let copy = menu.addItem(
            withTitle: "複製",
            action: #selector(menuCopy),
            keyEquivalent: ""
        )
        copy.target = self
        copy.isEnabled = hasSelection

        let paste = menu.addItem(
            withTitle: "貼上",
            action: #selector(menuPaste),
            keyEquivalent: ""
        )
        paste.target = self

        let duplicate = menu.addItem(
            withTitle: "製作副本",
            action: #selector(menuDuplicate),
            keyEquivalent: ""
        )
        duplicate.target = self
        duplicate.isEnabled = hasSelection

        let rename = menu.addItem(
            withTitle: "改名",
            action: #selector(menuRename),
            keyEquivalent: ""
        )
        rename.target = self
        rename.isEnabled = singleSelection

        let batchRename = menu.addItem(
            withTitle: "批量改名…",
            action: #selector(menuBatchRename),
            keyEquivalent: ""
        )
        batchRename.target = self
        batchRename.isEnabled = selectedItems().count > 1

        let zip = menu.addItem(
            withTitle: "壓縮成 ZIP",
            action: #selector(menuCreateZip),
            keyEquivalent: ""
        )
        zip.target = self
        zip.isEnabled = hasSelection

        let extract = menu.addItem(
            withTitle: "解壓 ZIP",
            action: #selector(menuExtractZip),
            keyEquivalent: ""
        )
        extract.target = self
        extract.isEnabled = selectedItems().contains {
            $0.url.pathExtension.lowercased() == "zip"
        }

        let download = menu.addItem(
            withTitle: "立即下載雲端檔案",
            action: #selector(menuCloudDownload),
            keyEquivalent: ""
        )
        download.target = self
        download.isEnabled = selectedItems().contains {
            $0.cloudAvailability == .onlineOnly || $0.cloudAvailability == .downloading
        }

        menu.addItem(.separator())
        let info = menu.addItem(
            withTitle: "取得資料",
            action: #selector(menuInfo),
            keyEquivalent: ""
        )
        info.target = self
        info.isEnabled = singleSelection

        let copyPath = menu.addItem(
            withTitle: "複製路徑",
            action: #selector(menuCopyPath),
            keyEquivalent: ""
        )
        copyPath.target = self
        copyPath.isEnabled = hasSelection

        let reveal = menu.addItem(
            withTitle: "在 Finder 顯示",
            action: #selector(menuReveal),
            keyEquivalent: ""
        )
        reveal.target = self
        reveal.isEnabled = hasSelection

        menu.addItem(.separator())
        let trash = menu.addItem(
            withTitle: "搬去垃圾桶",
            action: #selector(menuTrash),
            keyEquivalent: ""
        )
        trash.target = self
        trash.isEnabled = hasSelection
    }
}
