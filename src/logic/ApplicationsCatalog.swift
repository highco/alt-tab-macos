import Cocoa

struct ApplicationsCatalogItem: Hashable {
    let identifier: String
    let name: String
    let url: URL
    let icon: NSImage
}

class ApplicationsCatalog {
    static let shared = ApplicationsCatalog()

    private let userDefaultsKey = "applicationsCatalogRecentlyLaunched"
    private var cachedItems = [ApplicationsCatalogItem]()
    private var hasLoaded = false

    private let searchDirectories: [URL] = [
        URL(fileURLWithPath: "/Applications", isDirectory: true),
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
    ]

    func refreshIfNeeded() {
        guard !hasLoaded else { return }
        cachedItems = discoverApplications()
        hasLoaded = true
    }

    func orderedItems() -> [ApplicationsCatalogItem] {
        refreshIfNeeded()
        let storedOrder = UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
        var remaining = cachedItems
        var ordered = [ApplicationsCatalogItem]()

        for identifier in storedOrder {
            if let index = remaining.firstIndex(where: { $0.identifier == identifier }) {
                ordered.append(remaining.remove(at: index))
            }
        }
        ordered.append(contentsOf: remaining.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
        return ordered
    }

    func markAsLaunched(_ item: ApplicationsCatalogItem) {
        var storedOrder = UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
        storedOrder.removeAll { $0 == item.identifier }
        storedOrder.insert(item.identifier, at: 0)
        // keep only a reasonable subset
        if storedOrder.count > 100 {
            storedOrder = Array(storedOrder.prefix(100))
        }
        UserDefaults.standard.setValue(storedOrder, forKey: userDefaultsKey)
    }

    private func discoverApplications() -> [ApplicationsCatalogItem] {
        var results = [ApplicationsCatalogItem]()
        var identifiers = Set<String>()
        let fileManager = FileManager.default
        let workspace = NSWorkspace.shared

        for directory in searchDirectories {
            guard let enumerator = fileManager.enumerator(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                guard let bundle = Bundle(url: url) else { continue }
                let identifier = bundle.bundleIdentifier ?? url.path
                if identifiers.contains(identifier) { continue }
                let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let icon = workspace.icon(forFile: url.path)
                icon.size = NSSize(width: 64, height: 64)
                identifiers.insert(identifier)
                results.append(ApplicationsCatalogItem(identifier: identifier, name: displayName, url: url, icon: icon))
            }
        }
        return results
    }
}

