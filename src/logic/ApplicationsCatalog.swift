import Cocoa
import Darwin

extension Notification.Name {
    static let applicationsCatalogDidUpdate = Notification.Name("ApplicationsCatalogDidUpdate")
}

struct ApplicationsCatalogItem: Hashable {
    let identifier: String
    let name: String
    let url: URL
    let icon: NSImage
}

class ApplicationsCatalog {
    static let shared = ApplicationsCatalog()

    private let userDefaultsKey = "applicationsCatalogRecentlyLaunched"
    private let stateQueue = DispatchQueue(label: "app.alt-tab.catalog.state")
    private let workQueue = DispatchQueue(label: "app.alt-tab.catalog.discovery", qos: .userInitiated)

    private var cachedItems = [ApplicationsCatalogItem]()
    private var hasLoaded = false
    private var isRefreshing = false
    private var pendingRefresh = false
    private var directoryWatchers = [DispatchSourceFileSystemObject]()
    private let searchDirectories: [URL]

    private init() {
        searchDirectories = ApplicationsCatalog.buildSearchDirectories()
        startDirectoryWatchers()
        scheduleRefresh()
    }

    deinit {
        directoryWatchers.forEach { $0.cancel() }
    }

    func refreshIfNeeded() {
        var shouldRefresh = false
        stateQueue.sync {
            shouldRefresh = !hasLoaded && !isRefreshing
        }
        if shouldRefresh {
            scheduleRefresh()
        }
    }

    func orderedItems() -> [ApplicationsCatalogItem] {
        refreshIfNeeded()
        let storedOrder = UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
        let snapshot = stateQueue.sync { cachedItems }
        var remaining = snapshot
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
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
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

    private func scheduleRefresh(force: Bool = false) {
        var shouldStartWork = false
        stateQueue.sync {
            if !isRefreshing {
                isRefreshing = true
                pendingRefresh = false
                shouldStartWork = true
            } else if force {
                pendingRefresh = true
            }
        }

        guard shouldStartWork else { return }

        workQueue.async { [weak self] in
            guard let self = self else { return }
            let items = self.discoverApplications()
            var needsAnotherPass = false
            self.stateQueue.sync {
                self.cachedItems = items
                self.hasLoaded = true
                self.isRefreshing = false
                needsAnotherPass = self.pendingRefresh
                self.pendingRefresh = false
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .applicationsCatalogDidUpdate, object: self)
            }
            if needsAnotherPass {
                self.scheduleRefresh()
            }
        }
    }

    private func startDirectoryWatchers() {
        directoryWatchers.forEach { $0.cancel() }
        directoryWatchers.removeAll()

        for directory in searchDirectories {
            let fileDescriptor = open(directory.path, O_EVTONLY)
            guard fileDescriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.write, .rename, .delete],
                queue: workQueue
            )
            source.setEventHandler { [weak self] in
                self?.scheduleRefresh(force: true)
            }
            source.setCancelHandler {
                close(fileDescriptor)
            }
            source.resume()
            directoryWatchers.append(source)
        }
    }

    private static func buildSearchDirectories() -> [URL] {
        let fileManager = FileManager.default
        var directories = [URL]()
        var seen = Set<URL>()

        func appendIfValid(_ url: URL) {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized).inserted else { return }
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
            directories.append(standardized)
        }

        let domainMasks: [FileManager.SearchPathDomainMask] = [
            .systemDomainMask,
            .localDomainMask,
            .userDomainMask
        ]

        for mask in domainMasks {
            for url in fileManager.urls(for: .applicationDirectory, in: mask) {
                appendIfValid(url)
            }
        }

        let fallbackDirectories: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        fallbackDirectories.forEach { appendIfValid($0) }
        return directories
    }
}

