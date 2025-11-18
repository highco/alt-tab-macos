import Cocoa

enum MainWindowMode {
    case app
    case window
}

class ThumbnailsPanel: NSPanel {
    private static let shelfSpacing: CGFloat = 12

    var thumbnailsView = ThumbnailsView()
    private let applicationsShelfView = ApplicationsShelfView()
    private let panelBackgroundView: EffectView = makeAppropriateEffectView()
    private var catalogObserver: NSObjectProtocol?
    private(set) var mode: MainWindowMode = .app

    override var canBecomeKey: Bool { true }

    convenience init() {
        self.init(contentRect: .zero, styleMask: .nonactivatingPanel, backing: .buffered, defer: false)
        delegate = self
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        backgroundColor = .clear
        contentView! = panelBackgroundView
        panelBackgroundView.addSubview(thumbnailsView.contentView)
        panelBackgroundView.addSubview(applicationsShelfView)
        applicationsShelfView.onLaunchRequested = { [weak self] item in
            self?.launchApplication(item)
        }
        applicationsShelfView.onAppInteraction = { [weak self] in
            self?.enterAppMode()
        }
        // triggering AltTab before or during Space transition animation brings the window on the Space post-transition
        collectionBehavior = .canJoinAllSpaces
        // 2nd highest level possible; this allows the app to go on top of context menus
        // highest level is .screenSaver but makes drag and drop on top the main window impossible
        level = .popUpMenu
        // helps filter out this window from the thumbnails
        setAccessibilitySubrole(.unknown)
        // for VoiceOver
        setAccessibilityLabel(App.name)
        updateAppearance()
        observeApplicationsCatalog()
    }

    deinit {
        if let observer = catalogObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func updateAppearance() {
        hasShadow = Appearance.enablePanelShadow
        appearance = NSAppearance(named: Appearance.currentTheme == .dark ? .vibrantDark : .vibrantLight)
        panelBackgroundView.updateAppearance()
    }

    func updateContents() {
        CATransaction.begin()
        defer { CATransaction.commit() }
        CATransaction.setDisableActions(true)
        thumbnailsView.updateItemsAndLayout()
        guard App.app.appIsBeingUsed else { return }
        layoutShelfAndThumbnails()
        guard App.app.appIsBeingUsed else { return }
        NSScreen.preferred.repositionPanel(self)
    }

    func setMode(_ newMode: MainWindowMode) {
        guard mode != newMode else { return }
        mode = newMode
        if mode == .app {
            DispatchQueue.main.async { [weak self] in
                self?.applicationsShelfView.focusSearchField()
            }
        }
    }

    func enterAppMode() {
        setMode(.app)
    }

    func enterWindowMode() {
        setMode(.window)
    }

    var isInAppMode: Bool { mode == .app }

    func handleShelfArrowKey(_ direction: Direction) {
        applicationsShelfView.handleArrowKey(direction)
    }

    override func orderOut(_ sender: Any?) {
        if Preferences.fadeOutAnimation {
            NSAnimationContext.runAnimationGroup(
                { _ in animator().alphaValue = 0 },
                completionHandler: { super.orderOut(sender) }
            )
        } else {
            super.orderOut(sender)
        }
    }

    func show() {
        updateAppearance()
        refreshApplicationsShelf(resetSearch: true)
        enterAppMode()
        alphaValue = 1
        makeKeyAndOrderFront(nil)
        MouseEvents.toggle(true)
        thumbnailsView.scrollView.flashScrollers()
        DispatchQueue.main.async { [weak self] in
            self?.applicationsShelfView.focusSearchField()
        }
    }

    static func maxThumbnailsWidth() -> CGFloat {
        if Preferences.appearanceStyle == .titles,
           let readableWidth = ThumbnailView.widthOfComfortableReadability() {
            return (
                min(
                    NSScreen.preferred.frame.width * Appearance.maxWidthOnScreen,
                    readableWidth + Appearance.intraCellPadding * 2 + Appearance.appIconLabelSpacing + Appearance.iconSize
                    // widthOfLongestTitle + Appearance.intraCellPadding * 2 + Appearance.appIconLabelSpacing + Appearance.iconSize
                ) - Appearance.windowPadding * 2
            ).rounded()
        }
        return (NSScreen.preferred.frame.width * Appearance.maxWidthOnScreen - Appearance.windowPadding * 2).rounded()
    }

    static func maxThumbnailsHeight() -> CGFloat {
        let available = NSScreen.preferred.frame.height * Appearance.maxHeightOnScreen - Appearance.windowPadding * 2
        let reserved = ApplicationsShelfView.defaultHeight + ThumbnailsPanel.shelfSpacing
        return max(0, (available - reserved).rounded())
    }

    private func refreshApplicationsShelf(resetSearch: Bool = false) {
        if resetSearch {
            applicationsShelfView.reset()
        }
        applicationsShelfView.configure(items: ApplicationsCatalog.shared.orderedItems())
    }

    private func layoutShelfAndThumbnails() {
        let thumbnailsSize = thumbnailsView.contentView.frame.size
        thumbnailsView.contentView.frame.origin = .zero
        let width = thumbnailsSize.width
        let shelfHeight = ApplicationsShelfView.defaultHeight
        applicationsShelfView.frame = NSRect(
            x: 0,
            y: thumbnailsSize.height + ThumbnailsPanel.shelfSpacing,
            width: width,
            height: shelfHeight
        )
        let totalHeight = thumbnailsSize.height + ThumbnailsPanel.shelfSpacing + shelfHeight
        panelBackgroundView.frame = NSRect(origin: .zero, size: NSSize(width: width, height: totalHeight))
        setContentSize(panelBackgroundView.frame.size)
    }

    private func launchApplication(_ item: ApplicationsCatalogItem) {
        ApplicationsCatalog.shared.markAsLaunched(item)
        if #available(macOS 10.15, *) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: item.url, configuration: configuration) { _, error in
                self.handleLaunchCompletion(item: item, error: error)
            }
        } else {
            do {
                try NSWorkspace.shared.launchApplication(at: item.url, options: [], configuration: [:])
                handleLaunchCompletion(item: item, error: nil)
            } catch {
                handleLaunchCompletion(item: item, error: error)
            }
        }
    }

    private func handleLaunchCompletion(item: ApplicationsCatalogItem, error: Error?) {
        if let error = error {
            Logger.error("Failed to launch \(item.name): \(error.localizedDescription)")
            return
        }
        DispatchQueue.main.async {
            App.app.hideUi()
        }
    }

    private func observeApplicationsCatalog() {
        catalogObserver = NotificationCenter.default.addObserver(
            forName: .applicationsCatalogDidUpdate,
            object: ApplicationsCatalog.shared,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, App.app.appIsBeingUsed else { return }
            self.refreshApplicationsShelf()
        }
    }
}

extension ThumbnailsPanel: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // other windows can steal key focus from alt-tab; we make sure that if it's active, if keeps key focus
        // dispatching to the main queue is necessary to introduce a delay in scheduling the makeKey; otherwise it is ignored
        DispatchQueue.main.async {
            if App.app.appIsBeingUsed {
                App.app.thumbnailsPanel.makeKeyAndOrderFront(nil)
            }
        }
    }
}