import Cocoa

class InstalledApp {
    let name: String
    let bundleIdentifier: String?
    let url: URL
    var icon: CGImage?
    var lastLaunchedDate: Date?
    
    init(url: URL) {
        self.url = url
        self.bundleIdentifier = Bundle(url: url)?.bundleIdentifier
        
        // Get app name from URL
        self.name = url.deletingPathExtension().lastPathComponent
        
        // Load icon
        self.icon = NSWorkspace.shared.icon(forFile: url.path).cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    func launch() -> Bool {
        do {
            try NSWorkspace.shared.launchApplication(at: url, options: [], configuration: [:])
            return true
        } catch {
            return false
        }
    }
    
    func matchesSearchQuery(_ query: String) -> Bool {
        if query.isEmpty {
            return true
        }
        return name.localizedCaseInsensitiveContains(query)
    }
}

