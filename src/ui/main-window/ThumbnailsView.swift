import Cocoa

class ThumbnailsView {
    let scrollView = ScrollView()
    var contentView: EffectView!
    static var recycledViews = [ThumbnailView]()
    var rows = [[ThumbnailView]]()
    static var thumbnailsWidth = CGFloat(0.0)
    static var thumbnailsHeight = CGFloat(0.0)
    
    // App launcher components
    var appSearchField = AppSearchField()
    var appIconViews = [AppIconView]()
    var filteredApps: [InstalledApp] = []
    var focusedAppIndex: Int? = nil
    var isInAppsSection = false
    let appsSectionHeight: CGFloat = 190 // search field + app icons row with better spacing
    let searchFieldHeight: CGFloat = 36

    init() {
        contentView = makeAppropriateEffectView()
        contentView.addSubview(scrollView)
        // TODO: think about this optimization more
        (1...20).forEach { _ in ThumbnailsView.recycledViews.append(ThumbnailView()) }
        
        // Initialize app icon views
        (1...20).forEach { _ in appIconViews.append(AppIconView()) }
        
        // Setup app search field
        setupAppSearchField()
    }
    
    private func setupAppSearchField() {
        appSearchField.onTextChange = { [weak self] query in
            self?.filterApps(query: query)
        }
        contentView.addSubview(appSearchField)
    }
    
    private func filterApps(query: String) {
        filteredApps = InstalledAppsManager.shared.getFilteredApps(query: query)
        // Update the focused app index if we're already in apps section
        if isInAppsSection {
            focusedAppIndex = filteredApps.isEmpty ? nil : 0
        }
        updateAppIconsLayoutWithPositions()
    }

    func updateBackgroundView() {
        let newEffectView = makeAppropriateEffectView()
        scrollView.removeFromSuperview()
        newEffectView.addSubview(scrollView)
        contentView.superview?.replaceSubview(contentView, with: newEffectView)
        contentView = newEffectView
    }

    func reset() {
        // it would be nicer to remove this whole "reset" logic, and instead update each component to check Appearance properties before showing
        // Maybe in some Appkit willDraw() function that triggers before drawing it
        NSScreen.updatePreferred()
        Appearance.update()
        updateBackgroundView()
        for i in 0..<ThumbnailsView.recycledViews.count {
            ThumbnailsView.recycledViews[i] = ThumbnailView()
        }
        
        // Reset app-related state
        appSearchField.clear()
        isInAppsSection = false
        focusedAppIndex = nil
        appIconViews.forEach { $0.removeFromSuperview() }
        for i in 0..<appIconViews.count {
            appIconViews[i] = AppIconView()
        }
    }

    static func highlight(_ indexInRecycledViews: Int) {
        let view = recycledViews[indexInRecycledViews]
        view.indexInRecycledViews = indexInRecycledViews
        if view.frame != NSRect.zero {
            view.drawHighlight()
        }
    }

    func nextRow(_ direction: Direction, allowWrap: Bool = true) -> [ThumbnailView]? {
        let step = direction == .down ? 1 : -1
        if let currentRow = Windows.focusedWindow()?.rowIndex {
            var nextRow = currentRow + step
            if nextRow >= rows.count {
                if allowWrap {
                    nextRow = nextRow % rows.count
                } else {
                    return nil
                }
            } else if nextRow < 0 {
                if allowWrap {
                    nextRow = rows.count + nextRow
                } else {
                    return nil
                }
            }
            if ((step > 0 && nextRow < currentRow) || (step < 0 && nextRow > currentRow)) &&
                   (ATShortcut.lastEventIsARepeat || KeyRepeatTimer.timer?.isValid ?? false) {
                return nil
            }
            return rows[nextRow]
        }
        return nil
    }

    func navigateUpOrDown(_ direction: Direction, allowWrap: Bool = true) {
        // Handle navigation between apps and windows sections
        if direction == .up && !isInAppsSection && rows.count > 0 {
            // Check if we're on the first row of windows
            if let currentRow = Windows.focusedWindow()?.rowIndex, currentRow == 0 {
                // Move to apps section
                if !filteredApps.isEmpty {
                    // Clear window highlighting
                    let oldFocusedIndex = Windows.focusedWindowIndex
                    isInAppsSection = true
                    focusedAppIndex = 0
                    updateAppIconHighlights()
                    // Unhighlight the previously focused window
                    ThumbnailsView.recycledViews[oldFocusedIndex].drawHighlight()
                    return
                }
            }
        } else if direction == .down && isInAppsSection {
            // Move from apps to windows
            if !rows.isEmpty && !rows[0].isEmpty {
                isInAppsSection = false
                focusedAppIndex = nil
                updateAppIconHighlights()
                Windows.updateFocusedAndHoveredWindowIndex(0)
                return
            }
        }
        
        // If in apps section, stay in apps section for up/down
        if isInAppsSection {
            return
        }
        
        // Normal window navigation
        guard Windows.focusedWindowIndex < ThumbnailsView.recycledViews.count else { return }
        let focusedViewFrame = ThumbnailsView.recycledViews[Windows.focusedWindowIndex].frame
        let originCenter = NSMidX(focusedViewFrame)
        guard let targetRow = nextRow(direction, allowWrap: allowWrap), !targetRow.isEmpty else { return }
        let leftSide = originCenter < NSMidX(contentView.frame)
        let leadingSide = App.shared.userInterfaceLayoutDirection == .leftToRight ? leftSide : !leftSide
        let iterable = leadingSide ? targetRow : targetRow.reversed()
        guard let targetView = iterable.first(where: {
            if App.shared.userInterfaceLayoutDirection == .leftToRight {
                return leadingSide ? NSMaxX($0.frame) > originCenter : NSMinX($0.frame) < originCenter
            }
            return leadingSide ? NSMinX($0.frame) < originCenter : NSMaxX($0.frame) > originCenter
        }) ?? iterable.last else { return }
        guard let targetIndex = ThumbnailsView.recycledViews.firstIndex(of: targetView) else { return }
        Windows.updateFocusedAndHoveredWindowIndex(targetIndex)
    }
    
    func navigateLeftOrRight(_ direction: Direction) {
        if isInAppsSection {
            // Navigate within apps
            guard let currentIndex = focusedAppIndex else { return }
            let step = direction.step()
            let newIndex = currentIndex + step
            if newIndex >= 0 && newIndex < min(filteredApps.count, 10) {
                focusedAppIndex = newIndex
                updateAppIconHighlights()
            }
        }
        // Windows left/right navigation is handled by existing code in App.swift
    }
    
    func launchFocusedApp() {
        if isInAppsSection, let index = focusedAppIndex, index < filteredApps.count {
            launchApp(filteredApps[index])
        }
    }

    func updateItemsAndLayout() {
        // Load initial apps list
        if filteredApps.isEmpty {
            filteredApps = InstalledAppsManager.shared.getFilteredApps(query: "")
        }
        
        let widthMax = ThumbnailsPanel.maxThumbnailsWidth().rounded()
        
        // Layout apps section first
        layoutAppsSection(widthMax)
        
        if let (maxX, maxY, labelHeight) = layoutThumbnailViews(widthMax) {
            layoutParentViews(maxX, widthMax, maxY, labelHeight)
            if Preferences.alignThumbnails == .center {
                centerRows(maxX)
            }
            for row in rows {
                for (j, view) in row.enumerated() {
                    view.numberOfViewsInRow = row.count
                    view.isFirstInRow = j == 0
                    view.isLastInRow = j == row.count - 1
                    view.indexInRow = j
                }
            }
            highlightStartView()
        }
    }
    
    private func layoutAppsSection(_ widthMax: CGFloat) {
        // We'll position these from the top of the contentView after we know the full height
        // For now, just update the app icons layout - positioning will happen in layoutParentViews
        updateAppIconsLayout()
    }
    
    private func updateAppIconsLayout() {
        // Y position will be set later in layoutParentViews after we know the full height
        let spacing: CGFloat = 14 // Increased spacing between icons
        let horizontalPadding = Appearance.windowPadding + 8
        var currentX = horizontalPadding + spacing
        
        // Remove old app icon views from superview
        appIconViews.forEach { $0.removeFromSuperview() }
        
        // Show up to 10 apps
        let appsToShow = min(filteredApps.count, 10)
        for i in 0..<appsToShow {
            let appView = appIconViews[i]
            appView.frame = NSRect(
                x: currentX,
                y: 0, // Temporary, will be set in layoutParentViews
                width: AppIconView.cellWidth,
                height: AppIconView.cellHeight
            )
            appView.updateWithApp(filteredApps[i])
            appView.launchCallback = { [weak self] app in
                self?.launchApp(app)
            }
            contentView.addSubview(appView)
            currentX += AppIconView.cellWidth + spacing
        }
        
        // Update highlight for focused app
        updateAppIconHighlights()
    }
    
    private func updateAppIconsLayoutWithPositions() {
        // This version properly positions icons when called during filtering
        let spacing: CGFloat = 14
        let horizontalPadding = Appearance.windowPadding + 8
        var currentX = horizontalPadding + spacing
        
        // Calculate Y position from current contentView height
        let frameHeight = contentView.frame.height
        let appsStartY = frameHeight - Appearance.windowPadding - appsSectionHeight + 8
        let iconsY = appsStartY + 10
        
        // Remove old app icon views from superview
        appIconViews.forEach { $0.removeFromSuperview() }
        
        // Show up to 10 apps
        let appsToShow = min(filteredApps.count, 10)
        for i in 0..<appsToShow {
            let appView = appIconViews[i]
            appView.frame = NSRect(
                x: currentX,
                y: iconsY,
                width: AppIconView.cellWidth,
                height: AppIconView.cellHeight
            )
            appView.updateWithApp(filteredApps[i])
            appView.launchCallback = { [weak self] app in
                self?.launchApp(app)
            }
            contentView.addSubview(appView)
            currentX += AppIconView.cellWidth + spacing
        }
        
        // Update highlight for focused app
        updateAppIconHighlights()
    }
    
    private func updateAppIconHighlights() {
        for (index, appView) in appIconViews.enumerated() {
            appView.isFocused = (focusedAppIndex == index && isInAppsSection)
            appView.drawHighlight()
        }
    }
    
    private func launchApp(_ app: InstalledApp) {
        InstalledAppsManager.shared.launchApp(app)
        App.app.hideUi()
    }

    private func layoutThumbnailViews(_ widthMax: CGFloat) -> (CGFloat, CGFloat, CGFloat)? {
        let labelHeight = ThumbnailsView.recycledViews.first!.label.fittingSize.height
        let height = ThumbnailView.height(labelHeight)
        let isLeftToRight = App.shared.userInterfaceLayoutDirection == .leftToRight
        let thumbnailPadding = Appearance.interCellPadding + 4 // Slightly more padding for thumbnails
        let startingX = isLeftToRight ? thumbnailPadding : widthMax - thumbnailPadding
        var currentX = startingX
        // Start thumbnails from the bottom
        var currentY = thumbnailPadding
        var maxX = CGFloat(0)
        var maxY = currentY + height + thumbnailPadding
        var newViews = [ThumbnailView]()
        rows.removeAll(keepingCapacity: true)
        rows.append([ThumbnailView]())
        for (index, window) in Windows.list.enumerated() {
            guard App.app.appIsBeingUsed else { return nil }
            guard window.shouldShowTheUser else { continue }
            let view = ThumbnailsView.recycledViews[index]
            view.updateRecycledCellWithNewContent(window, index, height)
            let width = view.frame.size.width
            let thumbnailPadding = Appearance.interCellPadding + 4
            let projectedX = projectedWidth(currentX, width, thumbnailPadding).rounded(.down)
            if needNewLine(projectedX, widthMax) {
                currentX = startingX
                currentY = (currentY + height + thumbnailPadding).rounded(.down)
                view.frame.origin = CGPoint(x: localizedCurrentX(currentX, width), y: currentY)
                currentX = projectedWidth(currentX, width, thumbnailPadding).rounded(.down)
                maxY = max(currentY + height + thumbnailPadding, maxY)
                rows.append([ThumbnailView]())
            } else {
                view.frame.origin = CGPoint(x: localizedCurrentX(currentX, width), y: currentY)
                currentX = projectedX
                maxX = max(isLeftToRight ? currentX : widthMax - currentX, maxX)
            }
            rows[rows.count - 1].append(view)
            newViews.append(view)
            window.rowIndex = rows.count - 1
        }
        scrollView.documentView!.subviews = newViews
        return (maxX, maxY, labelHeight)
    }

    private func needNewLine(_ projectedX: CGFloat, _ widthMax: CGFloat) -> Bool {
        if App.shared.userInterfaceLayoutDirection == .leftToRight {
            return projectedX > widthMax
        }
        return projectedX < 0
    }

    private func projectedWidth(_ currentX: CGFloat, _ width: CGFloat, _ padding: CGFloat = 0) -> CGFloat {
        let usedPadding = padding > 0 ? padding : Appearance.interCellPadding
        if App.shared.userInterfaceLayoutDirection == .leftToRight {
            return currentX + width + usedPadding
        }
        return currentX - width - usedPadding
    }

    private func localizedCurrentX(_ currentX: CGFloat, _ width: CGFloat) -> CGFloat {
        App.shared.userInterfaceLayoutDirection == .leftToRight ? currentX : currentX - width
    }

    private func layoutParentViews(_ maxX: CGFloat, _ widthMax: CGFloat, _ maxY: CGFloat, _ labelHeight: CGFloat) {
        let heightMax = ThumbnailsPanel.maxThumbnailsHeight()
        ThumbnailsView.thumbnailsWidth = min(maxX, widthMax)
        ThumbnailsView.thumbnailsHeight = min(maxY, heightMax)
        let frameWidth = ThumbnailsView.thumbnailsWidth + Appearance.windowPadding * 2
        var frameHeight = ThumbnailsView.thumbnailsHeight + Appearance.windowPadding * 2 + appsSectionHeight
        let originX = Appearance.windowPadding
        // Position scroll view at the bottom (for thumbnails)
        let originY = Appearance.windowPadding
        if Preferences.appearanceStyle == .appIcons {
            // If there is title under the icon on the last line, the height of the title needs to be subtracted.
            frameHeight = frameHeight - Appearance.intraCellPadding - labelHeight
        }
        contentView.frame.size = NSSize(width: frameWidth, height: frameHeight)
        scrollView.frame.size = NSSize(width: min(maxX, widthMax), height: min(maxY, heightMax))
        scrollView.frame.origin = CGPoint(x: originX, y: originY)
        scrollView.contentView.frame.size = scrollView.frame.size
        if App.shared.userInterfaceLayoutDirection == .rightToLeft {
            let croppedWidth = widthMax - maxX
            scrollView.documentView!.subviews.forEach { $0.frame.origin.x -= croppedWidth }
        }
        scrollView.documentView!.frame.size = NSSize(width: maxX, height: maxY)
        if let existingTrackingArea = scrollView.trackingAreas.first {
            scrollView.removeTrackingArea(existingTrackingArea)
        }
        scrollView.addTrackingArea(NSTrackingArea(rect: scrollView.bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways], owner: scrollView, userInfo: nil))
        
        // Now position the apps section at the TOP (highest Y value)
        let horizontalPadding = Appearance.windowPadding + 8
        let searchFieldWidth = widthMax - 16
        let appsStartY = frameHeight - Appearance.windowPadding - appsSectionHeight + 8
        
        // Position search field at the top
        appSearchField.frame = NSRect(
            x: horizontalPadding,
            y: appsStartY + appsSectionHeight - searchFieldHeight - 8,
            width: searchFieldWidth,
            height: searchFieldHeight
        )
        
        // Position app icon views below search field
        let iconsY = appsStartY + 10
        for appView in appIconViews where appView.superview != nil {
            appView.frame.origin.y = iconsY
        }
    }

    func centerRows(_ maxX: CGFloat) {
        var rowStartIndex = 0
        var rowWidth = Appearance.interCellPadding
        var rowY = Appearance.interCellPadding
        for (index, window) in Windows.list.enumerated() {
            guard App.app.appIsBeingUsed else { return }
            guard window.shouldShowTheUser else { continue }
            let view = ThumbnailsView.recycledViews[index]
            if view.frame.origin.y == rowY {
                rowWidth += view.frame.size.width + Appearance.interCellPadding
            } else {
                shiftRow(maxX, rowWidth, rowStartIndex, index)
                rowStartIndex = index
                rowWidth = Appearance.interCellPadding + view.frame.size.width + Appearance.interCellPadding
                rowY = view.frame.origin.y
            }
        }
        shiftRow(maxX, rowWidth, rowStartIndex, Windows.list.count)
    }

    private func highlightStartView() {
        // Only highlight windows if we're not in apps section
        if !isInAppsSection {
            ThumbnailsView.highlight(Windows.focusedWindowIndex)
            if let hoveredWindowIndex = Windows.hoveredWindowIndex {
                ThumbnailsView.highlight(hoveredWindowIndex)
            }
        }
    }

    private func shiftRow(_ maxX: CGFloat, _ rowWidth: CGFloat, _ rowStartIndex: Int, _ index: Int) {
        let offset = ((maxX - rowWidth) / 2).rounded()
        if offset > 0 {
            for i in rowStartIndex..<index {
                ThumbnailsView.recycledViews[i].frame.origin.x += App.shared.userInterfaceLayoutDirection == .leftToRight ? offset : -offset
            }
        }
    }
}

class ScrollView: NSScrollView {
    // overriding scrollWheel() turns this false; we force it to be true to enable responsive scrolling
    override class var isCompatibleWithResponsiveScrolling: Bool { true }

    var isCurrentlyScrolling = false
    var previousTarget: ThumbnailView?

    convenience init() {
        self.init(frame: .zero)
        documentView = FlippedView(frame: .zero)
        drawsBackground = false
        hasVerticalScroller = true
        verticalScrollElasticity = .none
        scrollerStyle = .overlay
        scrollerKnobStyle = .light
        horizontalScrollElasticity = .none
        usesPredominantAxisScrolling = true
        observeScrollingEvents()
    }

    private func observeScrollingEvents() {
        NotificationCenter.default.addObserver(self, selector: #selector(scrollingStarted), name: NSScrollView.willStartLiveScrollNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scrollingEnded), name: NSScrollView.didEndLiveScrollNotification, object: nil)
    }

    @objc private func scrollingStarted() {
        isCurrentlyScrolling = true
    }

    @objc private func scrollingEnded() {
        isCurrentlyScrolling = false
    }

    private func resetHoveredWindow() {
        if let oldIndex = Windows.hoveredWindowIndex {
            Windows.hoveredWindowIndex = nil
            ThumbnailsView.highlight(oldIndex)
            ThumbnailsView.recycledViews[oldIndex].showOrHideWindowControls(false)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        // disable mouse hover during scrolling as it creates jank during elastic bounces at the start/end of the scrollview
        if isCurrentlyScrolling { return }
        if let hit = hitTest(App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream) {
            var target: NSView? = hit
            while !(target is ThumbnailView) && target != nil {
                target = target!.superview
            }
            if let target = target as? ThumbnailView {
                if previousTarget != target {
                    previousTarget?.showOrHideWindowControls(false)
                    previousTarget = target
                }
                target.mouseMoved()
            } else {
                if !checkIfWithinInterPadding() {
                    resetHoveredWindow()
                }
            }
        } else {
            resetHoveredWindow()
        }
    }

    override func mouseExited(with event: NSEvent) {
        resetHoveredWindow()
    }

    /// Checks whether the mouse pointer is within the padding area around a thumbnail.
    ///
    /// This is used to avoid gaps between thumbnail views where the mouse pointer might not be detected.
    ///
    /// @return `true` if the mouse pointer is within the padding area around a thumbnail; `false` otherwise.
    private func checkIfWithinInterPadding() -> Bool {
        if Preferences.appearanceStyle == .appIcons {
            let mouseLocation = App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream
            let mouseRect = NSRect(x: mouseLocation.x - Appearance.interCellPadding,
                y: mouseLocation.y - Appearance.interCellPadding,
                width: 2 * Appearance.interCellPadding,
                height: 2 * Appearance.interCellPadding)
            if let hoveredWindowIndex = Windows.hoveredWindowIndex {
                let thumbnail = ThumbnailsView.recycledViews[hoveredWindowIndex]
                let mouseRectInView = thumbnail.convert(mouseRect, from: nil)
                if thumbnail.bounds.intersects(mouseRectInView) {
                    return true
                }
            }
        }
        return false
    }

    /// holding shift and using the scrolling wheel will generate a horizontal movement
    /// shift can be part of shortcuts so we force shift scrolls to be vertical
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.shift) && event.scrollingDeltaY == 0 {
            let cgEvent = event.cgEvent!
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: cgEvent.getDoubleValueField(.scrollWheelEventDeltaAxis2))
            cgEvent.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: 0)
            super.scrollWheel(with: NSEvent(cgEvent: cgEvent)!)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

enum Direction {
    case right
    case left
    case leading
    case trailing
    case up
    case down

    func step() -> Int {
        if self == .left {
            return App.shared.userInterfaceLayoutDirection == .leftToRight ? -1 : 1
        } else if self == .right {
            return App.shared.userInterfaceLayoutDirection == .leftToRight ? 1 : -1
        }
        return self == .leading ? 1 : -1
    }
}
