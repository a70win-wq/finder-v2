import AppKit

enum CloudAvailability: Hashable {
    case local
    case onlineOnly
    case downloading
    case downloaded

    var title: String {
        switch self {
        case .local: return ""
        case .onlineOnly: return "雲端"
        case .downloading: return "下載中"
        case .downloaded: return "已下載"
        }
    }
}

struct FileItem: Hashable {
    let url: URL
    let isDirectory: Bool
    let isPackage: Bool
    let fileSize: Int64?
    let modifiedDate: Date?
    let kind: String
    var cloudAvailability: CloudAvailability = .local

    var name: String {
        FileManager.default.displayName(atPath: url.path)
    }

    var shouldOpenAsFolder: Bool {
        isDirectory && !isPackage
    }

    static func loadItem(at url: URL) -> FileItem? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey,
            .isHiddenKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              values.isHidden != true else {
            return nil
        }
        return FileItem(
            url: url,
            isDirectory: values.isDirectory == true,
            isPackage: values.isPackage == true,
            fileSize: values.fileSize.map(Int64.init),
            modifiedDate: values.contentModificationDate,
            kind: values.localizedTypeDescription ?? (values.isDirectory == true ? "資料夾" : "檔案"),
            cloudAvailability: cloudAvailability(from: values)
        )
    }

    static func load(
        from directory: URL,
        fileManager: FileManager = .default,
        showHidden: Bool = false
    ) throws -> [FileItem] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .localizedTypeDescriptionKey,
            .isHiddenKey,
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey
        ]
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: showHidden ? [] : [.skipsHiddenFiles]
        )

        return urls.compactMap { url in
            do {
                let values = try url.resourceValues(forKeys: keys)
                guard showHidden || values.isHidden != true else { return nil }
                return FileItem(
                    url: url,
                    isDirectory: values.isDirectory == true,
                    isPackage: values.isPackage == true,
                    fileSize: values.fileSize.map(Int64.init),
                    modifiedDate: values.contentModificationDate,
                    kind: values.localizedTypeDescription ?? (values.isDirectory == true ? "資料夾" : "檔案"),
                    cloudAvailability: cloudAvailability(from: values)
                )
            } catch {
                return nil
            }
        }
        .sorted {
            if $0.shouldOpenAsFolder != $1.shouldOpenAsFolder {
                return $0.shouldOpenAsFolder && !$1.shouldOpenAsFolder
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func cloudAvailability(from values: URLResourceValues) -> CloudAvailability {
        guard values.isUbiquitousItem == true else { return .local }
        switch values.ubiquitousItemDownloadingStatus {
        case .current?, .downloaded?:
            return .downloaded
        case .notDownloaded?:
            return .onlineOnly
        default:
            return .downloading
        }
    }
}

enum FileSortOption: Int, CaseIterable {
    case name
    case size
    case modified
    case kind

    var title: String {
        switch self {
        case .name: return "名稱"
        case .size: return "大小"
        case .modified: return "日期"
        case .kind: return "種類"
        }
    }
}

enum FileDisplayArrangement {
    static func items(
        from source: [FileItem],
        matching searchText: String,
        sortedBy sortOption: FileSortOption,
        ascending: Bool
    ) -> [FileItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? source
            : source.filter { $0.name.localizedCaseInsensitiveContains(query) }

        return filtered.sorted { left, right in
            if left.shouldOpenAsFolder != right.shouldOpenAsFolder {
                return left.shouldOpenAsFolder
            }

            let comparison: ComparisonResult
            switch sortOption {
            case .name:
                comparison = left.name.localizedStandardCompare(right.name)
            case .size:
                comparison = compare(left.fileSize ?? 0, right.fileSize ?? 0)
            case .modified:
                comparison = compare(
                    left.modifiedDate ?? .distantPast,
                    right.modifiedDate ?? .distantPast
                )
            case .kind:
                comparison = left.kind.localizedStandardCompare(right.kind)
            }

            if comparison == .orderedSame {
                return left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
            return ascending
                ? comparison == .orderedAscending
                : comparison == .orderedDescending
        }
    }

    private static func compare<T: Comparable>(_ left: T, _ right: T) -> ComparisonResult {
        if left < right { return .orderedAscending }
        if left > right { return .orderedDescending }
        return .orderedSame
    }
}

struct SidebarLocation: Hashable {
    let title: String
    let url: URL
    let symbolName: String
    var isFavorite = false
    var favoriteID: UUID?
    var isExternalVolume = false
}

struct FavoriteEntry: Codable, Hashable, Identifiable {
    let id: UUID
    var path: String
    var title: String
    var group: String

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}

final class FavoriteStore {
    static let shared = FavoriteStore()

    private let defaultsKey = "FinderV2FavoriteFolders"
    private let entriesKey = "FinderV2FavoriteEntriesV2"

    var urls: [URL] {
        entries.map(\.url)
    }

    var entries: [FavoriteEntry] {
        get {
            if let data = UserDefaults.standard.data(forKey: entriesKey),
               let decoded = try? JSONDecoder().decode([FavoriteEntry].self, from: data) {
                return decoded.filter { FileManager.default.fileExists(atPath: $0.path) }
            }
            let migrated = (UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
                .map { path in
                    FavoriteEntry(
                        id: UUID(),
                        path: URL(fileURLWithPath: path).standardizedFileURL.path,
                        title: FileManager.default.displayName(atPath: path),
                        group: "收藏"
                    )
                }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            save(migrated)
            return migrated
        }
    }

    func add(_ url: URL) {
        let standardized = url.standardizedFileURL
        var saved = entries
        guard !saved.contains(where: { $0.path == standardized.path }) else { return }
        saved.append(
            FavoriteEntry(
                id: UUID(),
                path: standardized.path,
                title: FileManager.default.displayName(atPath: standardized.path),
                group: "收藏"
            )
        )
        save(saved)
    }

    func remove(_ url: URL) {
        let path = url.standardizedFileURL.path
        save(entries.filter { $0.path != path })
    }

    func update(id: UUID, title: String, group: String) {
        var saved = entries
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[index].title = title
        saved[index].group = group
        save(saved)
    }

    func move(id: UUID, to destinationIndex: Int) {
        var saved = entries
        guard let sourceIndex = saved.firstIndex(where: { $0.id == id }) else { return }
        let entry = saved.remove(at: sourceIndex)
        saved.insert(entry, at: min(max(0, destinationIndex), saved.count))
        save(saved)
    }

    private func save(_ entries: [FavoriteEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: entriesKey)
        UserDefaults.standard.set(entries.map(\.path), forKey: defaultsKey)
    }
}

enum SidebarLocationProvider {
    static func locations(fileManager: FileManager = .default) -> [SidebarLocation] {
        let home = fileManager.homeDirectoryForCurrentUser
        var locations: [SidebarLocation] = [
            SidebarLocation(title: "主目錄", url: home, symbolName: "house"),
            SidebarLocation(title: "桌面", url: home.appendingPathComponent("Desktop"), symbolName: "menubar.dock.rectangle"),
            SidebarLocation(title: "文件", url: home.appendingPathComponent("Documents"), symbolName: "doc"),
            SidebarLocation(title: "下載項目", url: home.appendingPathComponent("Downloads"), symbolName: "arrow.down.circle")
        ]

        let fixedPaths = Set(locations.map { $0.url.standardizedFileURL.path })
        for favorite in FavoriteStore.shared.entries where !fixedPaths.contains(favorite.path) {
            locations.append(
                SidebarLocation(
                    title: favorite.group.isEmpty
                        ? favorite.title
                        : "\(favorite.group) · \(favorite.title)",
                    url: favorite.url,
                    symbolName: "star.fill",
                    isFavorite: true,
                    favoriteID: favorite.id
                )
            )
        }

        let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fileManager.fileExists(atPath: iCloud.path) {
            locations.append(SidebarLocation(title: "iCloud 雲碟", url: iCloud, symbolName: "icloud"))
        }

        let cloudStorage = home.appendingPathComponent("Library/CloudStorage")
        if let cloudURLs = try? fileManager.contentsOfDirectory(
            at: cloudStorage,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for cloudURL in cloudURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = cloudURL.lastPathComponent
                    .replacingOccurrences(of: "GoogleDrive-", with: "Google Drive – ")
                locations.append(SidebarLocation(title: name, url: cloudURL, symbolName: "externaldrive.badge.icloud"))
            }
        }

        let volumes = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        if let volumeURLs = try? fileManager.contentsOfDirectory(
            at: volumes,
            includingPropertiesForKeys: [.volumeIsInternalKey],
            options: [.skipsHiddenFiles]
        ) {
            for volumeURL in volumeURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                if volumeURL.lastPathComponent == "Macintosh HD" { continue }
                locations.append(
                    SidebarLocation(
                        title: volumeURL.lastPathComponent,
                        url: volumeURL,
                        symbolName: "externaldrive",
                        isExternalVolume: true
                    )
                )
            }
        }

        return locations.filter { fileManager.fileExists(atPath: $0.url.path) }
    }
}

enum FileFormatting {
    static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hant_HK")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    static func size(for item: FileItem) -> String {
        guard !item.isDirectory, let size = item.fileSize else { return "—" }
        return byteFormatter.string(fromByteCount: size)
    }

    static func date(_ date: Date?) -> String {
        guard let date else { return "—" }
        return dateFormatter.string(from: date)
    }
}

extension Notification.Name {
    static let finderV2FileSystemChanged = Notification.Name("FinderV2FileSystemChanged")
    static let finderV2OperationStatusChanged = Notification.Name("FinderV2OperationStatusChanged")
}
