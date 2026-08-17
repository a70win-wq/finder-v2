import AppKit
import Darwin

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

struct TransferRequest {
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

struct FileSystemIdentity: Equatable {
    let device: UInt64
    let inode: UInt64

    static func read(from url: URL) -> FileSystemIdentity? {
        var information = stat()
        let result = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return lstat(path, &information)
        }
        guard result == 0 else { return nil }
        return FileSystemIdentity(
            device: UInt64(information.st_dev),
            inode: UInt64(information.st_ino)
        )
    }
}

enum DirectoryUseInspector {
    static func processNameUsingDirectory(_ directory: URL) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-F", "pcn", "+d", directory.path]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return nil
        }

        let group = DispatchGroup()
        group.enter()
        var data = Data()
        DispatchQueue.global(qos: .userInitiated).async {
            data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            group.leave()
        }
        if group.wait(timeout: .now() + 2) == .timedOut {
            process.terminate()
            return nil
        }
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return processName(
            fromLsofOutput: text,
            matchingPath: directory.path,
            excludingPID: ProcessInfo.processInfo.processIdentifier
        )
    }

    static func processName(
        fromLsofOutput output: String,
        matchingPath path: String,
        excludingPID: Int32
    ) -> String? {
        var currentPID: Int32?
        var currentCommand = ""

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())
            switch field {
            case "p":
                currentPID = Int32(value)
                currentCommand = ""
            case "c":
                currentCommand = value
            case "n":
                guard value == path,
                      currentPID != excludingPID,
                      !currentCommand.isEmpty else {
                    continue
                }
                let lowercased = currentCommand.lowercased()
                if lowercased == "node"
                    || lowercased == "npm"
                    || lowercased == "vite"
                    || lowercased == "esbuild" {
                    return L("網站預覽程式")
                }
                return currentCommand
            default:
                continue
            }
        }
        return nil
    }
}

enum FileActionEngine {
    private struct CoordinatedMoveResult {
        let source: URL
        let destination: URL
        let sourceIdentity: FileSystemIdentity?
    }

    static func transfer(
        source: URL,
        destination: URL,
        operation: FileTransferOperation,
        replaceExisting: Bool,
        fileManager: FileManager = .default,
        progress: ((Int64) -> Void)? = nil,
        isCancelled: (() -> Bool)? = nil,
        directoryUseCheck: (URL) -> String? = DirectoryUseInspector.processNameUsingDirectory
    ) throws -> URL? {
        var sourceIsDirectory: ObjCBool = false
        let sourceWasDirectory = fileManager.fileExists(
            atPath: source.path,
            isDirectory: &sourceIsDirectory
        ) && sourceIsDirectory.boolValue

        if case .move = operation,
           sourceWasDirectory,
           let processName = directoryUseCheck(source) {
            throw FileOperationError.folderInUse(processName)
        }

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
                let moveResult = try coordinatedMove(
                    source: source,
                    destination: destination,
                    fileManager: fileManager
                )

                try verifyCompletedMove(
                    source: moveResult.source,
                    destination: moveResult.destination,
                    originalSourceIdentity: moveResult.sourceIdentity,
                    sourceWasDirectory: sourceWasDirectory,
                    fileManager: fileManager
                )
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
            if let trashedExistingURL = trashedExistingNSURL as URL? {
                do {
                    if fileManager.fileExists(atPath: destination.path) {
                        var ignoredPartialURL: NSURL?
                        try fileManager.trashItem(
                            at: destination,
                            resultingItemURL: &ignoredPartialURL
                        )
                    }
                    guard !fileManager.fileExists(atPath: destination.path) else {
                        throw FileOperationError.replacementRecoveryFailed
                    }
                    try fileManager.moveItem(
                        at: trashedExistingURL,
                        to: destination
                    )
                } catch {
                    throw FileOperationError.replacementRecoveryFailed
                }
            }
            throw error
        }
    }

    private static func coordinatedMove(
        source: URL,
        destination: URL,
        fileManager: FileManager
    ) throws -> CoordinatedMoveResult {
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordinationError: NSError?
        var moveError: Error?
        var result: CoordinatedMoveResult?

        coordinator.coordinate(
            writingItemAt: source,
            options: .forMoving,
            writingItemAt: destination,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedSource, coordinatedDestination in
            let sourceIdentity = FileSystemIdentity.read(from: coordinatedSource)
            coordinator.item(
                at: coordinatedSource,
                willMoveTo: coordinatedDestination
            )
            do {
                try fileManager.moveItem(
                    at: coordinatedSource,
                    to: coordinatedDestination
                )
                coordinator.item(
                    at: coordinatedSource,
                    didMoveTo: coordinatedDestination
                )
                result = CoordinatedMoveResult(
                    source: coordinatedSource,
                    destination: coordinatedDestination,
                    sourceIdentity: sourceIdentity
                )
            } catch {
                moveError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let moveError {
            throw moveError
        }
        guard let result else {
            throw FileOperationError.moveDestinationMissing
        }
        return result
    }

    private static func verifyCompletedMove(
        source: URL,
        destination: URL,
        originalSourceIdentity: FileSystemIdentity?,
        sourceWasDirectory: Bool,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: destination.path) else {
            throw FileOperationError.moveDestinationMissing
        }
        guard fileManager.fileExists(atPath: source.path) else {
            return
        }

        guard sourceWasDirectory, let originalSourceIdentity else {
            throw FileOperationError.moveSourceNotRemoved
        }

        let quarantine = source.deletingLastPathComponent()
            .appendingPathComponent(
                ".FinderV2-MoveCheck-\(UUID().uuidString)",
                isDirectory: true
            )
        guard renameAtomically(from: source, to: quarantine) else {
            throw FileOperationError.moveSourceNotRemoved
        }

        let quarantinedIdentity = FileSystemIdentity.read(from: quarantine)
        guard quarantinedIdentity == originalSourceIdentity else {
            try restoreQuarantinedSource(
                quarantine,
                to: source,
                fileManager: fileManager
            )
            throw FileOperationError.moveSourceRecreated
        }

        let removalResult = quarantine.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return Darwin.rmdir(path)
        }
        guard removalResult == 0 else {
            try restoreQuarantinedSource(
                quarantine,
                to: source,
                fileManager: fileManager
            )
            throw FileOperationError.moveSourceNotRemoved
        }
    }

    private static func renameAtomically(from source: URL, to destination: URL) -> Bool {
        source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath in
                guard let sourcePath, let destinationPath else { return false }
                return Darwin.rename(sourcePath, destinationPath) == 0
            }
        }
    }

    private static func restoreQuarantinedSource(
        _ quarantine: URL,
        to originalURL: URL,
        fileManager: FileManager
    ) throws {
        if !fileManager.fileExists(atPath: originalURL.path),
           renameAtomically(from: quarantine, to: originalURL) {
            return
        }

        let recoveryURL = FileTransferCoordinator.availableURL(
            for: originalURL.deletingLastPathComponent()
                .appendingPathComponent(
                    "\(originalURL.lastPathComponent)（搬移保留）",
                    isDirectory: true
                ),
            fileManager: fileManager
        )
        guard renameAtomically(from: quarantine, to: recoveryURL) else {
            throw FileOperationError.moveSourceRecoveryFailed
        }
        throw FileOperationError.moveSourceRecovered(recoveryURL.lastPathComponent)
    }

    private static func copyRegularFile(
        source: URL,
        destination: URL,
        fileManager: FileManager,
        progress: ((Int64) -> Void)?,
        isCancelled: (() -> Bool)?
    ) throws {
        if fileManager.fileExists(atPath: destination.path) {
            throw CocoaError(.fileWriteFileExists)
        }
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
            copyExtendedAttributes(from: source, to: destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private static func copyExtendedAttributes(from source: URL, to destination: URL) {
        _ = source.withUnsafeFileSystemRepresentation { sourcePath in
            destination.withUnsafeFileSystemRepresentation { destinationPath -> Int32 in
                guard let sourcePath, let destinationPath else { return -1 }
                return copyfile(
                    sourcePath,
                    destinationPath,
                    nil,
                    copyfile_flags_t(COPYFILE_XATTR | COPYFILE_ACL)
                )
            }
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
        var rememberedChoice = collisionChoice
        var reservedPaths = Set<String>()
        let requests = Self.planRequests(
            sources: sources,
            destinationFolder: destinationFolder,
            operation: operation,
            fileManager: fileManager,
            reservedPaths: &reservedPaths,
            rememberedChoice: &rememberedChoice,
            onFolderIntoSelf: {
                presentMessage(
                    title: L("唔可以搬入去"),
                    message: L("資料夾唔可以搬入自己入面。")
                )
            },
            askCollision: { name in
                askCollision(for: name)
            }
        )

        guard !requests.isEmpty else {
            completion?()
            return
        }

        let totalBytes = requests.reduce(Int64(0)) { total, request in
            let size = (try? request.source.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                .map(Int64.init) ?? 0
            return total + size
        }
        let actionName = operation == .copy ? L("複製") : L("搬移")
        TransferQueueCenter.shared.enqueue(
            title: String(format: L("%@ %ld 個項目"), actionName, requests.count)
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

    static func planRequests(
        sources: [URL],
        destinationFolder: URL,
        operation: FileTransferOperation,
        fileManager: FileManager = .default,
        reservedPaths: inout Set<String>,
        rememberedChoice: inout CollisionChoice?,
        onFolderIntoSelf: () -> Void = {},
        askCollision: (String) -> (choice: CollisionChoice, applyToAll: Bool)
    ) -> [TransferRequest] {
        var requests: [TransferRequest] = []

        for source in sources {
            let standardizedSource = source.standardizedFileURL
            var destination = destinationFolder
                .appendingPathComponent(source.lastPathComponent)
                .standardizedFileURL

            if standardizedSource == destination {
                continue
            }

            if isFolder(destinationFolder, inside: standardizedSource) {
                onFolderIntoSelf()
                continue
            }

            var replaceExisting = false
            let destinationPath = destination.path
            let reserved = reservedPaths.contains(destinationPath)
            let existsOnDisk = fileManager.fileExists(atPath: destinationPath)

            if existsOnDisk || reserved {
                let choice: CollisionChoice
                if let rememberedChoice {
                    choice = rememberedChoice
                } else {
                    let answer = askCollision(source.lastPathComponent)
                    choice = answer.choice
                    if answer.applyToAll {
                        rememberedChoice = answer.choice
                    }
                }
                switch choice {
                case .cancel:
                    continue
                case .replace:
                    if reserved {
                        // 呢個名已經預留給同一個批次入面另一個檔，唔可以覆蓋。
                        destination = availableURL(
                            for: destination,
                            fileManager: fileManager,
                            reservedPaths: reservedPaths
                        )
                    } else {
                        replaceExisting = true
                    }
                case .keepBoth:
                    destination = availableURL(
                        for: destination,
                        fileManager: fileManager,
                        reservedPaths: reservedPaths
                    )
                }
            }

            reservedPaths.insert(destination.path)
            requests.append(
                TransferRequest(
                    source: standardizedSource,
                    destination: destination,
                    operation: operation,
                    replaceExisting: replaceExisting
                )
            )
        }

        return requests
    }

    static func availableURL(
        for desiredURL: URL,
        fileManager: FileManager = .default,
        reservedPaths: Set<String> = []
    ) -> URL {
        let parent = desiredURL.deletingLastPathComponent()
        let extensionName = desiredURL.pathExtension
        let baseName: String
        if extensionName.isEmpty {
            baseName = desiredURL.lastPathComponent
        } else {
            baseName = desiredURL.deletingPathExtension().lastPathComponent
        }

        func isFree(_ url: URL) -> Bool {
            !fileManager.fileExists(atPath: url.path)
                && !reservedPaths.contains(url.path)
        }

        if isFree(desiredURL) {
            return desiredURL
        }

        var number = 2
        while true {
            let candidateName = extensionName.isEmpty
                ? "\(baseName) \(number)"
                : "\(baseName) \(number).\(extensionName)"
            let candidate = parent.appendingPathComponent(candidateName)
            if isFree(candidate) {
                return candidate
            }
            number += 1
        }
    }

    private func registerUndo(for transfers: [CompletedTransfer], with undoManager: UndoManager?) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { coordinator in
            coordinator.undo(transfers, undoManager: undoManager)
        }
        undoManager.setActionName(Self.undoActionName(for: transfers))
    }

    private static func undoActionName(for transfers: [CompletedTransfer]) -> String {
        let isCopy = transfers.allSatisfy { $0.operation == .copy }
        if transfers.count > 1 {
            return String(format: isCopy ? L("複製 %ld 個項目") : L("搬移 %ld 個項目"), transfers.count)
        }
        return isCopy ? L("複製項目") : L("搬移項目")
    }

    private func undo(_ transfers: [CompletedTransfer], undoManager: UndoManager?) {
        OperationStatusCenter.shared.begin()
        DispatchQueue.global(qos: .userInitiated).async {
            var errors: [Error] = []
            for transfer in transfers.reversed() {
                do {
                    try self.performUndo(transfer)
                } catch {
                    errors.append(error)
                }
            }

            OperationStatusCenter.shared.finish()
            DispatchQueue.main.async {
                undoManager?.registerUndo(withTarget: self) { coordinator in
                    coordinator.redo(transfers, undoManager: undoManager)
                }
                undoManager?.setActionName(Self.undoActionName(for: transfers))
                if let firstError = errors.first {
                    self.presentOperationError(firstError, extraCount: max(0, errors.count - 1))
                }
                NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
            }
        }
    }

    private func redo(_ transfers: [CompletedTransfer], undoManager: UndoManager?) {
        OperationStatusCenter.shared.begin()
        DispatchQueue.global(qos: .userInitiated).async {
            var errors: [Error] = []
            for transfer in transfers {
                do {
                    try self.performRedo(transfer)
                } catch {
                    errors.append(error)
                }
            }

            OperationStatusCenter.shared.finish()
            DispatchQueue.main.async {
                undoManager?.registerUndo(withTarget: self) { coordinator in
                    coordinator.undo(transfers, undoManager: undoManager)
                }
                undoManager?.setActionName(Self.undoActionName(for: transfers))
                if let firstError = errors.first {
                    self.presentOperationError(firstError, extraCount: max(0, errors.count - 1))
                }
                NotificationCenter.default.post(name: .finderV2FileSystemChanged, object: nil)
            }
        }
    }

    private func performUndo(_ transfer: CompletedTransfer) throws {
        let fileManager = FileManager.default
        switch transfer.operation {
        case .move:
            guard !fileManager.fileExists(atPath: transfer.source.path) else {
                throw FileOperationError.undoDestinationOccupied
            }
            guard fileManager.fileExists(atPath: transfer.destination.path) else {
                throw FileOperationError.undoSourceMissing
            }
            _ = try FileActionEngine.transfer(
                source: transfer.destination,
                destination: transfer.source,
                operation: .move,
                replaceExisting: false,
                fileManager: fileManager
            )
        case .copy:
            var ignored: NSURL?
            try fileManager.trashItem(at: transfer.destination, resultingItemURL: &ignored)
        }

        if let oldItem = transfer.replacedItemInTrash,
           !fileManager.fileExists(atPath: transfer.destination.path) {
            try fileManager.moveItem(at: oldItem, to: transfer.destination)
        }
    }

    private func performRedo(_ transfer: CompletedTransfer) throws {
        let fileManager = FileManager.default
        _ = try FileActionEngine.transfer(
            source: transfer.source,
            destination: transfer.destination,
            operation: transfer.operation,
            replaceExisting: transfer.replacedItemInTrash != nil,
            fileManager: fileManager
        )
    }

    private func askCollision(for name: String) -> (choice: CollisionChoice, applyToAll: Bool) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("已經有同名檔案")
        alert.informativeText = String(format: L("「%@」已經存在，你想點做？"), name)
        alert.addButton(withTitle: L("保留兩個"))
        alert.addButton(withTitle: L("取代"))
        alert.addButton(withTitle: L("略過"))
        let checkbox = NSButton(checkboxWithTitle: L("之後全部用呢個選擇"), target: nil, action: nil)
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

    private static func isFolder(_ possibleChild: URL, inside possibleParent: URL) -> Bool {
        let childPath = possibleChild.standardizedFileURL.path
        let parentPath = possibleParent.standardizedFileURL.path
        return childPath == parentPath || childPath.hasPrefix(parentPath + "/")
    }

    private func presentOperationError(_ error: Error, extraCount: Int) {
        var message = ErrorMessage.text(for: error)
        if extraCount > 0 {
            message += String(format: L("\n另外有 %ld 個項目未能完成。"), extraCount)
        }
        let title: String
        if let fileError = error as? FileOperationError {
            switch fileError {
            case .folderInUse:
                title = L("資料夾使用中")
            case .moveSourceRecreated:
                title = L("舊資料夾再次出現")
            case .moveSourceNotRemoved:
                title = L("搬移未完全完成")
            case .moveSourceRecovered, .moveSourceRecoveryFailed, .replacementRecoveryFailed:
                title = L("檔案已安全保留")
            default:
                title = L("做唔到呢個操作")
            }
        } else {
            title = L("做唔到呢個操作")
        }
        presentMessage(title: title, message: message)
    }

    private func presentMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: L("知道"))
        alert.runModal()
    }
}

enum FileRenameSupport {
    static func isSameItem(_ source: URL, as destination: URL) -> Bool {
        guard let sourceIdentity = FileSystemIdentity.read(from: source),
              let destinationIdentity = FileSystemIdentity.read(from: destination) else {
            return source.standardizedFileURL == destination.standardizedFileURL
        }
        return sourceIdentity == destinationIdentity
    }

    static func existsAsDifferentItem(
        _ destination: URL,
        source: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: destination.path) else { return false }
        return !isSameItem(source, as: destination)
    }

    static func moveItem(
        from source: URL,
        to destination: URL,
        fileManager: FileManager = .default
    ) throws {
        if fileManager.fileExists(atPath: destination.path),
           isSameItem(source, as: destination),
           source.standardizedFileURL != destination.standardizedFileURL {
            let temporary = source.deletingLastPathComponent()
                .appendingPathComponent(".FinderV2Rename-\(UUID().uuidString)")
            try fileManager.moveItem(at: source, to: temporary)
            do {
                try fileManager.moveItem(at: temporary, to: destination)
            } catch {
                try? fileManager.moveItem(at: temporary, to: source)
                throw error
            }
            return
        }
        try fileManager.moveItem(at: source, to: destination)
    }
}

enum FileOperationError: LocalizedError {
    case undoDestinationOccupied
    case undoSourceMissing
    case folderNotEmpty
    case cancelled
    case moveDestinationMissing
    case moveSourceNotRemoved
    case moveSourceRecreated
    case folderInUse(String)
    case moveSourceRecovered(String)
    case moveSourceRecoveryFailed
    case replacementRecoveryFailed

    var errorDescription: String? {
        switch self {
        case .undoDestinationOccupied:
            return L("原本位置而家已有同名檔案，所以未能還原。")
        case .undoSourceMissing:
            return L("搬移後嘅檔案已經搵唔到，所以未能還原。請先檢查新位置。")
        case .folderNotEmpty:
            return L("資料夾入面已有檔案，為免刪錯，所以未能還原。")
        case .cancelled:
            return L("操作已取消。")
        case .moveDestinationMissing:
            return L("搬移未完成，新位置搵唔到檔案。請檢查原本位置同新位置。")
        case .moveSourceNotRemoved:
            return L("新位置已有檔案，但舊位置仲有內容。為免刪錯，舊資料夾已保留，請檢查兩邊。")
        case .moveSourceRecreated:
            return L("檔案已搬到新位置，但有程式仲用緊舊資料夾，並喺舊位置重新整咗檔案。請先關閉相關程式，再檢查舊資料夾。")
        case let .folderInUse(processName):
            return String(format: L("「%@」仲用緊呢個資料夾。請先關閉佢，再搬一次。"), processName)
        case let .moveSourceRecovered(name):
            return String(format: L("為免刪錯，舊資料已安全保留為「%@」。請檢查新舊兩邊。"), name)
        case .moveSourceRecoveryFailed:
            return L("為免刪錯，舊資料已保留，但未能放回原名。請重新整理後檢查新舊兩邊。")
        case .replacementRecoveryFailed:
            return L("新舊檔案都有安全保留，但未能自動放回原位。請打開垃圾桶及目標資料夾檢查。")
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
                return L("呢個位置冇權限。你可以喺 Mac 設定俾 Finder v2.0 存取檔案。")
            case NSFileWriteOutOfSpaceError:
                return L("儲存空間唔夠，請先清理磁碟。")
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return L("檔案已經唔喺原本位置，請按重新整理。")
            case NSFileWriteFileExistsError:
                return L("目標位置已有同名檔案。")
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
