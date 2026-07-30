import Foundation

enum AcceptanceFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message): return message
        }
    }
}

@main
enum ManualAcceptanceRunner {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("FinderV2ManualAcceptance-\(UUID().uuidString)", isDirectory: true)
        let left = root.appendingPathComponent("左邊", isDirectory: true)
        let right = root.appendingPathComponent("右邊", isDirectory: true)
        try fileManager.createDirectory(at: left, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: right, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let moveSource = left.appendingPathComponent("搬移.txt")
        let moveDestination = right.appendingPathComponent("搬移.txt")
        try Data("move".utf8).write(to: moveSource)
        _ = try FileActionEngine.transfer(
            source: moveSource,
            destination: moveDestination,
            operation: .move,
            replaceExisting: false
        )
        try require(!fileManager.fileExists(atPath: moveSource.path), "搬移後原檔仍然存在")
        try require(fileManager.fileExists(atPath: moveDestination.path), "搬移後目標檔案不存在")

        let copySource = left.appendingPathComponent("複製.txt")
        let copyDestination = right.appendingPathComponent("複製.txt")
        try Data("copy".utf8).write(to: copySource)
        _ = try FileActionEngine.transfer(
            source: copySource,
            destination: copyDestination,
            operation: .copy,
            replaceExisting: false
        )
        try require(fileManager.fileExists(atPath: copySource.path), "複製後原檔不見了")
        try require(fileManager.fileExists(atPath: copyDestination.path), "複製後目標檔案不存在")

        let largeSource = left.appendingPathComponent("大檔案.bin")
        let largeDestination = right.appendingPathComponent("大檔案.bin")
        let largeData = Data(repeating: 0x5A, count: 16 * 1_024 * 1_024)
        try largeData.write(to: largeSource)
        _ = try FileActionEngine.transfer(
            source: largeSource,
            destination: largeDestination,
            operation: .copy,
            replaceExisting: false
        )
        let largeSize = try largeDestination.resourceValues(forKeys: [.fileSizeKey]).fileSize
        try require(largeSize == largeData.count, "大檔案複製大小不正確")

        let duplicate = right.appendingPathComponent("複製 2.txt")
        try Data().write(to: duplicate)
        let available = FileTransferCoordinator.availableURL(for: copyDestination)
        try require(available.lastPathComponent == "複製 3.txt", "保留兩個名稱不正確")

        let hidden = left.appendingPathComponent(".隱藏.txt")
        let folder = left.appendingPathComponent("資料夾", isDirectory: true)
        try Data().write(to: hidden)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: false)
        let items = try FileItem.load(from: left)
        try require(
            items.first?.url.standardizedFileURL.path == folder.standardizedFileURL.path,
            "資料夾沒有排在前面：\(items.map(\.name).joined(separator: ", "))"
        )
        try require(!items.contains { $0.url == hidden }, "隱藏檔案不應顯示")

        let sidebarTitles = Set(SidebarLocationProvider.locations().map(\.title))
        for requiredTitle in ["主目錄", "桌面", "文件", "下載項目"] {
            try require(sidebarTitles.contains(requiredTitle), "常用位置缺少 \(requiredTitle)")
        }

        print("PASS：搬移、複製、大檔案、保留兩個、清單排序及常用位置全部通過")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw AcceptanceFailure.failed(message)
        }
    }
}
