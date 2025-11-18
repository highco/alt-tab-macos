import Cocoa

class InstalledAppsManager {
    static let shared = InstalledAppsManager()
    
    private var allApps: [InstalledApp] = []
    private var recentlyLaunchedApps: [String: Date] = [:] // bundleIdentifier -> date
    private let recentAppsKey = "recentlyLaunchedApps"
    
    private init() {
        loadRecentlyLaunchedApps()
        discoverApps()
    }
    
    private func discoverApps() {
        // Get all applications from the system by scanning /Applications and ~/Applications
        var appUrls: [URL] = []
        let fileManager = FileManager.default
        let applicationDirs = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications"
        ]
        
        for dir in applicationDirs {
            if let enumerator = fileManager.enumerator(atPath: dir) {
                for case let file as String in enumerator {
                    if file.hasSuffix(".app") {
                        let fullPath = dir + "/" + file
                        appUrls.append(URL(fileURLWithPath: fullPath))
                        enumerator.skipDescendants()
                    }
                }
            }
        }
        
        allApps = appUrls.map { InstalledApp(url: $0) }
        
        // Set last launched dates from persisted data
        for app in allApps {
            if let bundleId = app.bundleIdentifier,
               let date = recentlyLaunchedApps[bundleId] {
                app.lastLaunchedDate = date
            }
        }
        
        sortApps()
    }
    
    private func sortApps() {
        // Sort by recently launched first, then alphabetically
        allApps.sort { app1, app2 in
            let date1 = app1.lastLaunchedDate ?? Date.distantPast
            let date2 = app2.lastLaunchedDate ?? Date.distantPast
            
            if date1 != date2 {
                return date1 > date2
            }
            return app1.name.localizedCaseInsensitiveCompare(app2.name) == .orderedAscending
        }
    }
    
    func getFilteredApps(query: String) -> [InstalledApp] {
        if query.isEmpty {
            return allApps
        }
        return allApps.filter { $0.matchesSearchQuery(query) }
    }
    
    func launchApp(_ app: InstalledApp) {
        if app.launch() {
            // Update recency
            if let bundleId = app.bundleIdentifier {
                let now = Date()
                app.lastLaunchedDate = now
                recentlyLaunchedApps[bundleId] = now
                saveRecentlyLaunchedApps()
                sortApps()
            }
        }
    }
    
    private func loadRecentlyLaunchedApps() {
        if let data = UserDefaults.standard.dictionary(forKey: recentAppsKey) as? [String: TimeInterval] {
            recentlyLaunchedApps = data.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }
    
    private func saveRecentlyLaunchedApps() {
        let data = recentlyLaunchedApps.mapValues { $0.timeIntervalSince1970 }
        UserDefaults.standard.set(data, forKey: recentAppsKey)
    }
    
    func refresh() {
        discoverApps()
    }
}

