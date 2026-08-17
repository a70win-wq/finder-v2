import AppKit

enum FolderComparisonState: String, Hashable {
    case onlyHere
    case different
    case same
}

struct FolderComparisonResult {
    let left: [String: FolderComparisonState]
    let right: [String: FolderComparisonState]

    var leftOnlyCount: Int { left.values.filter { $0 == .onlyHere }.count }
    var rightOnlyCount: Int { right.values.filter { $0 == .onlyHere }.count }
    var differentCount: Int { left.values.filter { $0 == .different }.count }
    var sameCount: Int { left.values.filter { $0 == .same }.count }
}

enum FolderComparisonEngine {
    static func compare(
        left: [FileItem],
        right: [FileItem],
        depth: Int = 0
    ) -> FolderComparisonResult {
        // 用真實檔名做 key，避免 displayName 撞名（隱藏副檔名）時 crash。
        let leftMap = keyedItems(left)
        let rightMap = keyedItems(right)
        let names = Set(leftMap.keys).union(rightMap.keys)
        var leftStates: [String: FolderComparisonState] = [:]
        var rightStates: [String: FolderComparisonState] = [:]

        for name in names {
            guard let leftItem = leftMap[name] else {
                rightStates[name] = .onlyHere
                continue
            }
            guard let rightItem = rightMap[name] else {
                leftStates[name] = .onlyHere
                continue
            }

            let state = comparisonState(left: leftItem, right: rightItem, depth: depth)
            leftStates[name] = state
            rightStates[name] = state
        }
        return FolderComparisonResult(left: leftStates, right: rightStates)
    }

    static func syncSources(from source: [FileItem], to destination: [FileItem]) -> [URL] {
        let destinationMap = keyedItems(destination)
        return source.compactMap { item in
            guard let existing = destinationMap[item.fileSystemName] else {
                return item.url
            }
            guard item.isDirectory == existing.isDirectory else { return item.url }
            if item.isDirectory { return nil }
            let sourceDate = item.modifiedDate?.timeIntervalSince1970 ?? 0
            let destinationDate = existing.modifiedDate?.timeIntervalSince1970 ?? 0
            return item.fileSize != existing.fileSize || sourceDate > destinationDate + 1
                ? item.url
                : nil
        }
    }

    static func syncOperations(
        from source: [FileItem],
        to destination: [FileItem],
        destinationFolder: URL,
        depth: Int = 0
    ) -> [SyncOperation] {
        let destinationMap = keyedItems(destination)
        var operations: [SyncOperation] = []

        for item in source {
            let key = item.fileSystemName
            guard let existing = destinationMap[key] else {
                operations.append(SyncOperation(source: item.url, destinationFolder: destinationFolder))
                continue
            }
            if item.shouldOpenAsFolder, existing.shouldOpenAsFolder, depth < 6 {
                let childSource = (try? FileItem.load(from: item.url, showHidden: true)) ?? []
                let childDestination = (try? FileItem.load(from: existing.url, showHidden: true)) ?? []
                operations.append(
                    contentsOf: syncOperations(
                        from: childSource,
                        to: childDestination,
                        destinationFolder: existing.url,
                        depth: depth + 1
                    )
                )
                continue
            }
            guard item.isDirectory == existing.isDirectory else {
                operations.append(SyncOperation(source: item.url, destinationFolder: destinationFolder))
                continue
            }
            if item.isDirectory { continue }
            let sourceDate = item.modifiedDate?.timeIntervalSince1970 ?? 0
            let destinationDate = existing.modifiedDate?.timeIntervalSince1970 ?? 0
            if item.fileSize != existing.fileSize || sourceDate > destinationDate + 1 {
                operations.append(SyncOperation(source: item.url, destinationFolder: destinationFolder))
            }
        }
        return operations
    }

    private static func keyedItems(_ items: [FileItem]) -> [String: FileItem] {
        Dictionary(items.map { ($0.fileSystemName, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private static func comparisonState(
        left: FileItem,
        right: FileItem,
        depth: Int
    ) -> FolderComparisonState {
        if left.shouldOpenAsFolder, right.shouldOpenAsFolder, depth < 6 {
            let leftChildren = (try? FileItem.load(from: left.url, showHidden: true)) ?? []
            let rightChildren = (try? FileItem.load(from: right.url, showHidden: true)) ?? []
            let nested = compare(left: leftChildren, right: rightChildren, depth: depth + 1)
            let same = nested.leftOnlyCount == 0
                && nested.rightOnlyCount == 0
                && nested.differentCount == 0
            return same ? .same : .different
        }

        let sameKind = left.isDirectory == right.isDirectory
        let sameSize = left.isDirectory || left.fileSize == right.fileSize
        let leftDate = left.modifiedDate?.timeIntervalSince1970 ?? 0
        let rightDate = right.modifiedDate?.timeIntervalSince1970 ?? 0
        let sameDate = abs(leftDate - rightDate) < 2
        return sameKind && sameSize && sameDate ? .same : .different
    }
}

struct SyncOperation: Equatable {
    let source: URL
    let destinationFolder: URL
}

enum BatchRenameMode: Int, CaseIterable {
    case prefix
    case suffix
    case replace
    case number

    var title: String {
        switch self {
        case .prefix: return L("名稱前面加字")
        case .suffix: return L("名稱後面加字")
        case .replace: return L("搵字及取代")
        case .number: return L("順序編號")
        }
    }
}

enum BatchRenameEngine {
    static func proposedNames(
        for items: [FileItem],
        mode: BatchRenameMode,
        firstText: String,
        secondText: String = ""
    ) -> [String] {
        items.enumerated().map { index, item in
            let parts = nameParts(for: item)
            let renamedBase: String
            switch mode {
            case .prefix:
                renamedBase = firstText + parts.base
            case .suffix:
                renamedBase = parts.base + firstText
            case .replace:
                renamedBase = parts.base.replacingOccurrences(of: firstText, with: secondText)
            case .number:
                renamedBase = "\(firstText)\(index + 1)"
            }
            return parts.ext.isEmpty ? renamedBase : "\(renamedBase).\(parts.ext)"
        }
    }

    static func apply(
        items: [FileItem],
        names: [String],
        fileManager: FileManager = .default
    ) throws -> [(old: URL, new: URL)] {
        var temporaryPairs: [(old: URL, temporary: URL, final: URL)] = []
        do {
            for (item, name) in zip(items, names) {
                let parent = item.url.deletingLastPathComponent()
                let finalURL = parent.appendingPathComponent(name)
                if item.url.standardizedFileURL == finalURL.standardizedFileURL {
                    continue
                }
                let temporary = parent.appendingPathComponent(
                    ".FinderV2Rename-\(UUID().uuidString)"
                )
                try FileRenameSupport.moveItem(
                    from: item.url,
                    to: temporary,
                    fileManager: fileManager
                )
                temporaryPairs.append((item.url, temporary, finalURL))
            }
            for pair in temporaryPairs {
                try FileRenameSupport.moveItem(
                    from: pair.temporary,
                    to: pair.final,
                    fileManager: fileManager
                )
            }
            return temporaryPairs.map { (old: $0.old, new: $0.final) }
        } catch {
            for pair in temporaryPairs.reversed() {
                if fileManager.fileExists(atPath: pair.temporary.path) {
                    try? fileManager.moveItem(at: pair.temporary, to: pair.old)
                } else if fileManager.fileExists(atPath: pair.final.path),
                          !fileManager.fileExists(atPath: pair.old.path) {
                    try? fileManager.moveItem(at: pair.final, to: pair.old)
                }
            }
            throw error
        }
    }

    static func nameParts(for item: FileItem) -> (base: String, ext: String) {
        let lastComponent = item.url.lastPathComponent
        let keepExtension = !item.isDirectory || item.isPackage
        let pathExtension = keepExtension ? item.url.pathExtension : ""
        let stripped = item.url.deletingPathExtension().lastPathComponent
        if pathExtension.isEmpty || stripped.isEmpty || stripped == "." {
            return (lastComponent, "")
        }
        return (stripped, pathExtension)
    }
}

enum ArchiveEngine {
    static func zipEntryPath(for url: URL, in directory: URL) -> String {
        let filePath = url.standardizedFileURL.path
        let dirPath = directory.standardizedFileURL.path
        if filePath == dirPath {
            return "."
        }
        if filePath.hasPrefix(dirPath + "/") {
            return String(filePath.dropFirst(dirPath.count + 1))
        }
        return url.lastPathComponent
    }

    static func createZip(from urls: [URL], in directory: URL, named name: String) throws -> URL {
        let safeName = name.lowercased().hasSuffix(".zip") ? name : "\(name).zip"
        let destination = FileTransferCoordinator.availableURL(
            for: directory.appendingPathComponent(safeName)
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = directory
        process.arguments = ["-q", "-r", "-y", destination.path]
            + urls.map { zipEntryPath(for: $0, in: directory) }
        try run(process)
        return destination
    }

    static func extractZip(_ source: URL, to directory: URL) throws -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        let destination = FileTransferCoordinator.availableURL(
            for: directory.appendingPathComponent(base, isDirectory: true)
        )
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", source.path, destination.path]
            try run(process)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private static func run(_ process: Process) throws {
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? L("壓縮工具發生錯誤。")
            throw NSError(
                domain: "FinderV2Archive",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}

enum TransferJobState: String {
    case waiting = "等候中"
    case running = "處理中"
    case paused = "已暫停"
    case completed = "已完成"
    case cancelled = "已取消"
    case failed = "失敗"

    /// 介面顯示用（rawValue 保持穩定，顯示先翻譯）。
    var displayTitle: String {
        L(rawValue)
    }
}

final class TransferQueueCenter {
    static let shared = TransferQueueCenter()

    struct Snapshot {
        let id: UUID
        let title: String
        let state: TransferJobState
    }

    private final class JobControl {
        let condition = NSCondition()
        var state: TransferJobState = .waiting
        var cancelRequested = false
    }

    private let lock = NSLock()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "Finder v2.0 搬檔工作"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private var jobs: [(id: UUID, title: String, control: JobControl)] = []

    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return jobs.contains { [.waiting, .running, .paused].contains($0.control.state) }
    }

    var snapshots: [Snapshot] {
        lock.lock()
        defer { lock.unlock() }
        return jobs.reversed().map { Snapshot(id: $0.id, title: $0.title, state: $0.control.state) }
    }

    @discardableResult
    func enqueue(title: String, work: @escaping (_ shouldStop: @escaping () -> Bool) throws -> Void) -> UUID {
        let id = UUID()
        let control = JobControl()
        lock.lock()
        jobs.append((id, title, control))
        lock.unlock()
        notify()

        queue.addOperation { [weak self, weak control] in
            guard let self, let control else { return }
            control.condition.lock()
            if control.cancelRequested {
                control.state = .cancelled
                control.condition.unlock()
                self.notify()
                return
            }
            control.state = .running
            control.condition.unlock()
            self.notify()

            do {
                try work {
                    control.condition.lock()
                    while control.state == .paused && !control.cancelRequested {
                        control.condition.wait()
                    }
                    let shouldStop = control.cancelRequested
                    control.condition.unlock()
                    return shouldStop
                }
                control.condition.lock()
                control.state = control.cancelRequested ? .cancelled : .completed
                control.condition.unlock()
            } catch {
                control.condition.lock()
                control.state = control.cancelRequested ? .cancelled : .failed
                control.condition.unlock()
            }
            self.notify()
        }
        return id
    }

    func pause(_ id: UUID) {
        withControl(id) { control in
            if control.state == .running { control.state = .paused }
        }
    }

    func resume(_ id: UUID) {
        withControl(id) { control in
            if control.state == .paused {
                control.state = .running
                control.condition.broadcast()
            }
        }
    }

    func cancel(_ id: UUID) {
        withControl(id) { control in
            guard [.waiting, .running, .paused].contains(control.state) else { return }
            control.cancelRequested = true
            if control.state == .waiting { control.state = .cancelled }
            control.condition.broadcast()
        }
    }

    func cancelRunning() {
        lock.lock()
        let id = jobs.first {
            $0.control.state == .running || $0.control.state == .paused
        }?.id
        lock.unlock()
        if let id { cancel(id) }
    }

    func clearFinished() {
        lock.lock()
        jobs.removeAll { [.completed, .cancelled, .failed].contains($0.control.state) }
        lock.unlock()
        notify()
    }

    private func withControl(_ id: UUID, action: (JobControl) -> Void) {
        lock.lock()
        let control = jobs.first(where: { $0.id == id })?.control
        lock.unlock()
        guard let control else { return }
        control.condition.lock()
        action(control)
        control.condition.unlock()
        notify()
    }

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .finderV2TransferQueueChanged, object: nil)
        }
    }
}

extension Notification.Name {
    static let finderV2TransferQueueChanged = Notification.Name("FinderV2TransferQueueChanged")
}

final class TransferQueueWindowController: NSWindowController {
    static let shared = TransferQueueWindowController()

    private let tableView = NSTableView()
    private var jobs: [TransferQueueCenter.Snapshot] = []
    private let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("job"))
    private let stateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("state"))
    private let pauseButton = NSButton(title: L("暫停"), target: nil, action: #selector(pauseSelected))
    private let resumeButton = NSButton(title: L("繼續"), target: nil, action: #selector(resumeSelected))
    private let cancelButton = NSButton(title: L("取消工作"), target: nil, action: #selector(cancelSelected))
    private let clearButton = NSButton(title: L("清走已完成"), target: nil, action: #selector(clearFinished))

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 330),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L("搬檔工作清單")
        window.minSize = NSSize(width: 480, height: 260)
        super.init(window: window)
        buildContent()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queueChanged),
            name: .finderV2TransferQueueChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageChanged),
            name: .finderV2LanguageChanged,
            object: nil
        )
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        reload()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        nameColumn.title = L("工作")
        nameColumn.width = 380
        stateColumn.title = L("狀態")
        stateColumn.width = 120
        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(stateColumn)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scrollView)

        pauseButton.target = self
        resumeButton.target = self
        cancelButton.target = self
        clearButton.target = self
        let buttons = NSStackView(views: [pauseButton, resumeButton, cancelButton, clearButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            scrollView.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    @objc private func languageChanged() {
        window?.title = L("搬檔工作清單")
        nameColumn.title = L("工作")
        stateColumn.title = L("狀態")
        pauseButton.title = L("暫停")
        resumeButton.title = L("繼續")
        cancelButton.title = L("取消工作")
        clearButton.title = L("清走已完成")
        reload()
    }

    @objc private func queueChanged() {
        reload()
    }

    @objc private func pauseSelected() {
        selectedJob.map { TransferQueueCenter.shared.pause($0.id) }
    }

    @objc private func resumeSelected() {
        selectedJob.map { TransferQueueCenter.shared.resume($0.id) }
    }

    @objc private func cancelSelected() {
        selectedJob.map { TransferQueueCenter.shared.cancel($0.id) }
    }

    @objc private func clearFinished() {
        TransferQueueCenter.shared.clearFinished()
    }

    private var selectedJob: TransferQueueCenter.Snapshot? {
        let row = tableView.selectedRow
        return row >= 0 && row < jobs.count ? jobs[row] : nil
    }

    private func reload() {
        let selectedID = selectedJob?.id
        jobs = TransferQueueCenter.shared.snapshots
        tableView.reloadData()
        if let selectedID, let index = jobs.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
    }
}

extension TransferQueueWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        jobs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < jobs.count, let identifier = tableColumn?.identifier else { return nil }
        let cellID = NSUserInterfaceItemIdentifier("Queue-\(identifier.rawValue)")
        let cell = (tableView.makeView(withIdentifier: cellID, owner: self) as? NSTableCellView)
            ?? NSTableCellView()
        cell.identifier = cellID
        if cell.textField == nil {
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            cell.textField = label
            cell.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 5),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField?.stringValue = identifier.rawValue == "job"
            ? jobs[row].title
            : jobs[row].state.displayTitle
        return cell
    }
}
