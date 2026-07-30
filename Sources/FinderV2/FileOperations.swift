import AppKit

enum FileTransferOperation {
    case move
    case copy
}

enum CollisionChoice: Equatable {
    case cancel
    case replace
    case keepBoth
}

final class OperationStatusCenter {
    static let shared = OperationStatusCenter()

    struct ProgressSnapshot {
        let totalItems: Int
        let completedItems: Int
        let totalBytes: Int64
        let completedBytes: Int64
        let currentName: String
        let elapsed: TimeInterval
        let isCancellationRequested: Bool

        var fractionCompleted: Double {
            if totalBytes > 0 {
                return min(1, Double(completedBytes) / Double(totalBytes))
            }
            guard totalItems > 0 else { return 0 }
            return min(1, Double(completedItems) / Double(totalItems))
        }

        var bytesPerSecond: Double {
            guard elapsed > 0 else { return 0 }
            return Double(completedBytes) / elapsed
        }

        var estimatedRemaining: TimeInterval? {
            let speed = bytesPerSecond
            guard totalBytes > 0, speed > 0 else { return nil }
            return Double(max(0, totalBytes - completedBytes)) / speed
        }
    }

    private struct DetailedProgress {
        let totalItems: Int
        let totalBytes: Int64
        let startedAt: Date
        var completedItems = 0
        var completedBytes: Int64 = 0
        var currentName = ""
        var currentItemBytes: Int64 = 0
        var currentItemCompletedBytes: Int64 = 0
        var cancellationRequested = false
    }

    private let lock = NSLock()
    private var activeOperations = 0
    private var detailedProgress: DetailedProgress?
    private var lastProgressNotification = Date.distantPast

    var isBusy: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeOperations > 0
    }

    var progressSnapshot: ProgressSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let progress = detailedProgress else { return nil }
        return ProgressSnapshot(
            totalItems: progress.totalItems,
            completedItems: progress.completedItems,
            totalBytes: progress.totalBytes,
            completedBytes: progress.completedBytes,
            currentName: progress.currentName,
            elapsed: Date().timeIntervalSince(progress.startedAt),
            isCancellationRequested: progress.cancellationRequested
        )
    }

    func begin(count: Int = 1) {
        lock.lock()
        activeOperations += max(1, count)
        lock.unlock()
        notify()
    }

    func finish(count: Int = 1) {
        lock.lock()
        activeOperations = max(0, activeOperations - max(1, count))
        lock.unlock()
        notify()
    }

    func beginDetailed(totalItems: Int, totalBytes: Int64) {
        lock.lock()
        activeOperations += 1
        detailedProgress = DetailedProgress(
            totalItems: max(1, totalItems),
            totalBytes: max(0, totalBytes),
            startedAt: Date()
        )
        lastProgressNotification = .distantPast
        lock.unlock()
        notify()
    }

    func beginItem(name: String, bytes: Int64) {
        lock.lock()
        detailedProgress?.currentName = name
        detailedProgress?.currentItemBytes = max(0, bytes)
        detailedProgress?.currentItemCompletedBytes = 0
        lock.unlock()
        notify()
    }

    func advance(bytes: Int64) {
        guard bytes > 0 else { return }
        lock.lock()
        detailedProgress?.completedBytes += bytes
        detailedProgress?.currentItemCompletedBytes += bytes
        let now = Date()
        let shouldNotify = now.timeIntervalSince(lastProgressNotification) >= 0.15
        if shouldNotify {
            lastProgressNotification = now
        }
        lock.unlock()
        if shouldNotify {
            notify()
        }
    }

    func completeItem() {
        lock.lock()
        if var progress = detailedProgress {
            let remaining = max(0, progress.currentItemBytes - progress.currentItemCompletedBytes)
            progress.completedBytes += remaining
            progress.completedItems += 1
            progress.currentItemCompletedBytes += remaining
            detailedProgress = progress
        }
        lock.unlock()
        notify()
    }

    func requestCancellation() {
        lock.lock()
        detailedProgress?.cancellationRequested = true
        lock.unlock()
        notify()
    }

    var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return detailedProgress?.cancellationRequested == true
    }

    func finishDetailed() {
        lock.lock()
        activeOperations = max(0, activeOperations - 1)
        detailedProgress = nil
        lock.unlock()
        notify()
    }

    private func notify() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .finderV2OperationStatusChanged, object: nil)
        }
    }
}

private struct TransferRequest {
    let source: URL
    let destination: URL
    let operation: FileTransferOperation
    let replaceExisting: Bool
}

private struct CompletedTransfer {
    let source: URL
    let destination: URL
    let operation: FileTransferOperation
    let replacedItemInTrash: URL?
}

enum FileActionEngine {
    static func transfer(
        source: URL,
        destination: URL,
        operation: FileTransferOperation,
        replaceExisting: Bool,
        fileManager: FileManager = .default,
        progress: ((Int64) -> Void)? = nil,
        isCancelled: (() -> Bool)? = nil
    ) throws -> URL? {
        var trashedExistingNSURL: NSURL?
        if replaceExisting, fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(
                at: destination,
                resultingItemURL: &trashedExistingNSURL
            )
        }

        do {
            if isCancelled?() == true {
                throw FileOperationError.cancelled
            }
            switch operation {
            case .move:
                try fileManager.moveItem(at: source, to: destination)
            case .copy:
                let values = try? source.resourceValues(forKeys: [.isRegularFileKey])
                if values?.isRegularFile == true, progress != nil || isCancelled != nil {
                    try copyRegularFile(
                        source: source,
                        destination: destination,
                        fileManager: fileManager,
                        progress: progress,
                        isCancelled: isCancelled
                    )
                } else {
                    try fileManager.copyItem(at: source, to: destination)
                }
            }
            return trashedExistingNSURL as URL?
        } catch {
            if let trashedExistingURL = trashedExistingNSURL as URL?,
               !fileManager.fileExists(atPath: destination.path) {
                try? fileManager.moveItem(at: trashedExistingURL, to: destination)
            }
            throw error
        }
    }

    private static func copyRegularFile(
        source: URL,
        destination: URL,
        fileManager: FileManager,
        progress: ((Int64) -> Void)?,
        isCancelled: (() -> Bool)?
    ) throws {
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        do {
            let reader = try FileHandle(forReadingFrom: source)
            let writer = try FileHandle(forWritingTo: destination)
            defer {
                try? reader.close()
                try? writer.close()
            }

            while true {
                if isCancelled?() == true {
                    throw FileOperationError.cancelled
                }
                guard let data = try reader.read(upToCount: 1_048_576), !data.isEmpty else {
                    break
                }
                try writer.write(contentsOf: data)
                progress?(Int64(data.count))
            }

            if let attributes = try? fileManager.attributesOfItem(atPath: source.path) {
                try? fileManager.setAttributes(attributes, ofItemAtPath: destination.path)
            }
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }
}

final class FileTransferCoordinator: NSObject {
    static let shared = FileTransferCoordinator()

    func transfer(
        sources: [URL],
        to destinationFolder: URL,
        operation: FileTransferOperation,
        undoManager: UndoManager?,
        collisionChoice: CollisionChoice? = nil,
        completion: (() -> Void)? = nil
    ) {
        precondition(Thread.isMainThread)

        let fileManager = FileManager.default
        var requests: [TransferRequest] = []
        var rememberedChoice = collisionChoice

        for source in sources {
            let standardizedSource = source.standardizedFileURL
            var destination = destinationFolder
                .appendingPathComponent(source.lastPathComponent)
                .standardizedFileURL

            if standardizedSource == destination {
                continue
            }

            if isFolder(destinationFolder, inside: standardizedSource) {
                presentMessage(
                    title: "唔可以搬入去",
                    message: "資料夾唔可以搬入自己入面。"
                )
                continue
            }

            var replaceExisting = false
            if fileManager.fileExists(atPath: destination.path) {
                let choice: CollisionChoice
                if let rememberedChoice {
                    choice = rememberedChoice
                } else {
                    let answer = askCollision(for: source.lastPathComponent)
                    choice = answer.choice
                    if answer.applyToAll {
                        rememberedChoice = answer.choice
                    }
                }
                switch choice {
                case .cancel:
                    continue
                case .replace:
                    replaceExisting = true
                case .keepBoth:
                    destination = Self.availableURL(for: destination, fileManager: fileManager)
                }
            }

            requests.append(
                TransferRequest(
                    source: standardizedSource,
                    destination: destination,
                    operation: operation,
                    replaceExisting: replaceExisting
                )
            )
        }

        guard !requests.isEmpty else {
            completion?()
            return
        }

        let totalBytes = requests.reduce(Int64(0)) { total, request in
            let size = (try? request.source.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map(Int64.init) ?? 0
            return total + size
        }
        let actionName = operation == .copy ? "複製" : "搬移"
        TransferQueueCenter.shared.enqueue(
            title: "\(actionName) \(requests.count) 個項目"
        ) { shouldStop in
            OperationStatusCenter.shared.beginDetailed(
                totalItems: requests.count,
                totalBytes: totalBytes
            )
            var completed: [CompletedTransfer] = []
            var errors: [Error] = []

            for request in requests {
                if shouldStop() || OperationStatusCenter.shared.isCancellationRequested {
                    break
                }
                let itemBytes = (try? request.source.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                    .map(Int64.init) ?? 0
                OperationStatusCenter.shared.beginItem(
                    name: request.source.lastPathComponent,
                    bytes: itemBytes
                )
                do {
                    let trashedExistingURL = try FileActionEngine.transfer(
                        source: request.source,
                        destination: request.destination,
                        operation: request.operation,
                        replaceExisting: request.replaceExisting,
                        fileManager: fileManager,
                        progress: { OperationStatusCenter.shared.advance(bytes: $0) },
                        isCancelled: {
                            shouldStop() || OperationStatusCenter.shared.isCancellationRequested
                        }
                    )

                    completed.append(
                        CompletedTransfer(
                            source: request.source,
                            destination: request.destination,
                            operation: request.operation,
                            replacedItemInTrash: trashedExistingURL
                        )
                    )
                } catch {
                    if let fileError = error as? FileOperationError,
                       case .cancelled = fileError {
                        // User asked to stop, so this is not an error.
                    } else {
                        errors.append(error)
                    }
                }
                OperationStatusCenter.shared.completeItem()
            }

            OperationStatusCenter.shared.finishDetailed()
            DispatchQueue.main.async {
                if !completed.isEmpty {
                    self.registerUndo(for: completed, with: undoManager)
                }
                if let firstError = errors.first {
                    self.presentOperationError(firstError, extraCount: max(0, errors.count - 1))
                }
                NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
                completion?()
            }
        }
    }

    static func availableURL(for desiredURL: URL, fileManager: FileManager = .default) -> URL {
        guard fileManager.fileExists(atPath: desiredURL.path) else { return desiredURL }

        let parent = desiredURL.deletingLastPathComponent()
        let extensionName = desiredURL.pathExtension
        let baseName: String
        if extensionName.isEmpty {
            baseName = desiredURL.lastPathComponent
        } else {
            baseName = desiredURL.deletingPathExtension().lastPathComponent
        }

        var number = 2
        while true {
            let candidateName = extensionName.isEmpty
                ? "\(baseName) \(number)"
                : "\(baseName) \(number).\(extensionName)"
            let candidate = parent.appendingPathComponent(candidateName)
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            number += 1
        }
    }

    private func registerUndo(for transfers: [CompletedTransfer], with undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.beginUndoGrouping()
        for transfer in transfers {
            undoManager.registerUndo(withTarget: self) { coordinator in
                coordinator.undo(transfer)
            }
        }
        undoManager.endUndoGrouping()
        undoManager.setActionName(transfers.count > 1 ? "搬移 \(transfers.count) 個項目" : "搬移項目")
    }

    private func undo(_ transfer: CompletedTransfer) {
        let fileManager = FileManager.default
        OperationStatusCenter.shared.begin()
        DispatchQueue.global(qos: .userInitiated).async {
            var caughtError: Error?
            do {
                switch transfer.operation {
                case .move:
                    guard !fileManager.fileExists(atPath: transfer.source.path) else {
                        throw FileOperationError.undoDestinationOccupied
                    }
                    try fileManager.moveItem(at: transfer.destination, to: transfer.source)
                case .copy:
                    var ignored: NSURL?
                    try fileManager.trashItem(at: transfer.destination, resultingItemURL: &ignored)
                }

                if let oldItem = transfer.replacedItemInTrash,
                   !fileManager.fileExists(atPath: transfer.destination.path) {
                    try fileManager.moveItem(at: oldItem, to: transfer.destination)
                }
            } catch {
                caughtError = error
            }

            OperationStatusCenter.shared.finish()
            DispatchQueue.main.async {
                if let caughtError {
                    self.presentOperationError(caughtError, extraCount: 0)
                }
                NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
            }
        }
    }

    private func askCollision(for name: String) -> (choice: CollisionChoice, applyToAll: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "已經有同名檔案"
        alert.informativeText = "「\(name)」已經存在，你想點做？"
        alert.addButton(withTitle: "保留兩個")
        alert.addButton(withTitle: "取代")
        alert.addButton(withTitle: "略過")
        let checkbox = NSButton(checkboxWithTitle: "之後全部用呢個選擇", target: nil, action: nil)
        checkbox.frame = NSRect(x: 0, y: 0, width: 220, height: 24)
        alert.accessoryView = checkbox

        let choice: CollisionChoice
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            choice = .keepBoth
        case .alertSecondButtonReturn:
            choice = .replace
        default:
            choice = .cancel
        }
        return (choice, checkbox.state == .on)
    }

    private func isFolder(_ possibleChild: URL, inside possibleParent: URL) -> Bool {
        let childPath = possibleChild.standardizedFileURL.path
        let parentPath = possibleParent.standardizedFileURL.path
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }

    private func presentOperationError(_ error: Error, extraCount: Int) {
        var message = ErrorMessage.text(for: error)
        if extraCount > 0 {
            message += "\n另外有 \(extraCount) 個項目未能完成。"
        }
        presentMessage(title: "做唔到呢個操作", message: message)
    }

    private func presentMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "知道")
        alert.runModal()
    }
}

enum FileOperationError: LocalizedError {
    case undoDestinationOccupied
    case folderNotEmpty
    case cancelled

    var errorDescription: String? {
        switch self {
        case .undoDestinationOccupied:
            return "原本位置而家已有同名檔案，所以未能還原。"
        case .folderNotEmpty:
            return "資料夾入面已有檔案，為免刪錯，所以未能還原。"
        case .cancelled:
            return "操作已取消。"
        }
    }
}

enum ErrorMessage {
    static func text(for error: Error) -> String {
        if let fileError = error as? FileOperationError {
            return fileError.localizedDescription
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return "呢個位置冇權限。你可以喺 Mac 設定俾 Finder v2.0 存取檔案。"
            case NSFileWriteOutOfSpaceError:
                return "儲存空間唔夠，請先清理磁碟。"
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return "檔案已經唔喺原本位置，請按重新整理。"
            case NSFileWriteFileExistsError:
                return "目標位置已有同名檔案。"
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
