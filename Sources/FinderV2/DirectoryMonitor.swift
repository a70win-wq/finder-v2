import Darwin
import Foundation

@MainActor
final class DirectoryMonitor {
    private let debounceInterval: TimeInterval
    private let eventQueue = DispatchQueue(
        label: "com.a70win.finderv2.directory-monitor",
        qos: .utility
    )

    private var source: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private var monitoredURL: URL?
    private var changeHandler: (() -> Void)?

    init(debounceInterval: TimeInterval = 0.45) {
        self.debounceInterval = debounceInterval
    }

    func startMonitoring(_ url: URL, onChange: @escaping () -> Void) {
        stopMonitoring()

        let standardizedURL = url.standardizedFileURL
        let fileDescriptor = open(standardizedURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        monitoredURL = standardizedURL
        changeHandler = onChange

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: eventQueue
        )
        source.setEventHandler { [weak self] in
            DispatchQueue.main.async {
                self?.directoryDidChange()
            }
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        self.source = source
        source.resume()
    }

    func stopMonitoring() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        source?.cancel()
        source = nil
        monitoredURL = nil
        changeHandler = nil
    }

    private func directoryDidChange() {
        guard source != nil else { return }

        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.changeHandler?()
        }
        debounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + debounceInterval,
            execute: workItem
        )
    }

    deinit {
        source?.cancel()
        debounceWorkItem?.cancel()
    }
}
