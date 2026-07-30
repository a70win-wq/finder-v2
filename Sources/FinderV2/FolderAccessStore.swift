import Foundation

final class FolderAccessStore {
    static let shared = FolderAccessStore()

    private let defaultsKey = "FinderV2GrantedFolderBookmarks"
    private var grantedRoots: [URL] = []

    private init() {
        restoreBookmarks()
    }

    func hasAccess(to url: URL) -> Bool {
        let targetPath = url.standardizedFileURL.path
        return grantedRoots.contains { root in
            let rootPath = root.standardizedFileURL.path
            return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
        }
    }

    func needsPermission(for url: URL) -> Bool {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        let protectedRoots = [
            homePath + "/Desktop",
            homePath + "/Documents",
            homePath + "/Downloads",
            homePath + "/Library/CloudStorage",
            homePath + "/Library/Mobile Documents"
        ]
        if protectedRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return true
        }
        return path.hasPrefix("/Volumes/") && path != "/Volumes/Macintosh HD"
    }

    func grantAccess(to url: URL) throws {
        let standardized = url.standardizedFileURL
        if hasAccess(to: standardized) { return }

        let data = try standardized.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        var stored = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] ?? []
        stored.append(data)
        UserDefaults.standard.set(stored, forKey: defaultsKey)
        _ = standardized.startAccessingSecurityScopedResource()
        grantedRoots.append(standardized)
    }

    private func restoreBookmarks() {
        let stored = UserDefaults.standard.array(forKey: defaultsKey) as? [Data] ?? []
        var refreshed: [Data] = []

        for data in stored {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }
            _ = url.startAccessingSecurityScopedResource()
            grantedRoots.append(url.standardizedFileURL)

            if isStale,
               let newData = try? url.bookmarkData(
                   options: .withSecurityScope,
                   includingResourceValuesForKeys: nil,
                   relativeTo: nil
               ) {
                refreshed.append(newData)
            } else {
                refreshed.append(data)
            }
        }

        if refreshed.count != stored.count {
            UserDefaults.standard.set(refreshed, forKey: defaultsKey)
        }
    }
}
