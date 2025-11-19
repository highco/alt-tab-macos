import Cocoa
import IOKit.ps

class ThumbnailsPanel: NSPanel {
    var thumbnailsView = ThumbnailsView()
    private let applicationsShelfView = ApplicationsShelfView()
    private let infoBar = InfoBar()
    private let panelBackgroundView: EffectView = makeLiquidGlassEffectView()
    private var catalogObserver: NSObjectProtocol?
    
    var userHasSelectedAWindow: Bool = false

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
        panelBackgroundView.addSubview(infoBar)
        applicationsShelfView.onLaunchRequested = { [weak self] item in
            self?.launchApplication(item)
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

    func handleShelfArrowKey(_ direction: Direction) {
        applicationsShelfView.handleArrowKey(direction)
    }

    override func sendEvent(_ event: NSEvent) {
        print("ThumbnailsPanel sendEvent: \(event)")
        // Intercept Tab key before it reaches any control (including search field)
        if event.type == .keyDown && event.keyCode == 48 { // Tab key
            userHasSelectedAWindow = true
            Windows.cycleFocusedWindowIndex(1, allowWrap: true)
            return
        }
        // Intercept Escape key to hide UI
        if event.type == .keyDown && event.keyCode == 53 { // Escape key
            App.app.hideUi()
            return
        }
        super.sendEvent(event)
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
        alphaValue = 1
        userHasSelectedAWindow = false
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
        let reserved = ApplicationsShelfView.defaultHeight + Appearance.panelSectionSpacing * 2 + InfoBar.defaultHeight
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
        thumbnailsView.contentView.frame.origin = NSPoint(x: Appearance.panelPadding, y: Appearance.panelPadding)
        let width = thumbnailsSize.width
        let shelfHeight = ApplicationsShelfView.defaultHeight
        let spacing = Appearance.panelSectionSpacing

        applicationsShelfView.frame = NSRect(
            x: Appearance.panelPadding,
            y: thumbnailsSize.height + spacing + Appearance.panelPadding,
            width: width,
            height: shelfHeight
        )
        
        let infoBarHeight = InfoBar.defaultHeight
        infoBar.frame = NSRect(
            x: Appearance.panelPadding,
            y: thumbnailsSize.height + spacing + shelfHeight + spacing + Appearance.panelPadding,
            width: width,
            height: infoBarHeight
        )
        
        let totalHeight = thumbnailsSize.height + spacing + shelfHeight + spacing + infoBarHeight
        panelBackgroundView.frame = NSRect(origin: .zero, size: NSSize(width: width + 2 * Appearance.panelPadding, height: totalHeight + 2 * Appearance.panelPadding))
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

class InfoBar: NSView {
    static var defaultHeight: CGFloat { Appearance.infoBarHeight }

    private let dateLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let batteryLabel = NSTextField(labelWithString: "")
    private let batteryIcon = BatteryIconView()
    private var timer: Timer?

    init() {
        super.init(frame: .zero)
        setupUI()
        updateData()
        startTimer()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    private func setupUI() {
        let font = NSFont.systemFont(ofSize: Appearance.infoBarHeight * 0.5)
        let clockFont = NSFont.systemFont(ofSize: Appearance.infoBarClockHeight)
        
        [dateLabel, batteryLabel].forEach {
            $0.font = font
            $0.textColor = Appearance.fontColor
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        timeLabel.font = clockFont
        timeLabel.textColor = Appearance.fontColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        batteryIcon.translatesAutoresizingMaskIntoConstraints = false

        addSubview(dateLabel)
        addSubview(timeLabel)
        addSubview(batteryLabel)
        addSubview(batteryIcon)

        let batteryHeight = Appearance.infoBarHeight * 0.42
        let batteryWidth = batteryHeight * 2.2

        NSLayoutConstraint.activate([
            // Date Left
            dateLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Appearance.panelSectionSpacing),
            dateLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Time Center
            timeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            // Battery Right
            batteryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Appearance.panelSectionSpacing),
            batteryLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            
            batteryIcon.trailingAnchor.constraint(equalTo: batteryLabel.leadingAnchor, constant: -6),
            batteryIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            batteryIcon.widthAnchor.constraint(equalToConstant: batteryWidth),
            batteryIcon.heightAnchor.constraint(equalToConstant: batteryHeight)
        ])
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateData()
        }
    }

    private func updateData() {
        let now = Date()
        
        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none
        dateLabel.stringValue = dateFormatter.string(from: now)

        // Time
        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .medium
        timeLabel.stringValue = timeFormatter.string(from: now)

        // Battery
        if let (level, isCharging) = getBatteryInfo() {
            batteryLabel.stringValue = "\(level)%"
            batteryIcon.level = Double(level) / 100.0
            batteryIcon.isCharging = isCharging
            batteryIcon.isHidden = false
            batteryLabel.isHidden = false
        } else {
            batteryIcon.isHidden = true
            batteryLabel.isHidden = true
        }
        
        // Update colors
        [dateLabel, timeLabel, batteryLabel].forEach {
             $0.textColor = Appearance.fontColor
        }
    }

    private func getBatteryInfo() -> (Int, Bool)? {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        
        for source in sources ?? [] {
            let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
            
            if let type = description?[kIOPSTypeKey] as? String, type == kIOPSInternalBatteryType {
                let currentCapacity = description?[kIOPSCurrentCapacityKey] as? Int ?? 0
                let maxCapacity = description?[kIOPSMaxCapacityKey] as? Int ?? 0
                let isCharging = description?[kIOPSIsChargingKey] as? Bool ?? false
                
                let percentage = maxCapacity > 0 ? (Double(currentCapacity) / Double(maxCapacity) * 100.0) : 0
                return (Int(percentage), isCharging)
            }
        }
        return nil
    }
}

class BatteryIconView: NSView {
    var level: Double = 1.0 { didSet { needsDisplay = true } }
    var isCharging: Bool = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let color = Appearance.fontColor
        color.setStroke()
        color.setFill()
        
        // Body
        let bodyRect = NSRect(x: 0, y: 0, width: bounds.width - 3, height: bounds.height)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 1, yRadius: 1)
        bodyPath.lineWidth = 1
        bodyPath.stroke()
        
        // Nub
        let nubRect = NSRect(x: bounds.width - 3, y: bounds.height / 2 - 2, width: 3, height: 4)
        let nubPath = NSBezierPath(roundedRect: nubRect, xRadius: 1, yRadius: 1)
        nubPath.fill()
        
        // Level
        if level > 0 {
            let margin: CGFloat = 2
            let maxLevelWidth = bodyRect.width - margin * 2
            let levelWidth = maxLevelWidth * CGFloat(level)
            let levelRect = NSRect(x: margin, y: margin, width: levelWidth, height: bodyRect.height - margin * 2)
            let levelPath = NSBezierPath(roundedRect: levelRect, xRadius: 0.5, yRadius: 0.5)
            levelPath.fill()
        }
    }
}
