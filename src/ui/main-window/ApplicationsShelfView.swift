import Cocoa

class ApplicationsShelfView: NSView {
    static var defaultHeight: CGFloat {
        let paddingVertical: CGFloat = 12
        let searchFieldHeight: CGFloat = 34
        let buttonHeight: CGFloat = 82
        let rowSpacing: CGFloat = Appearance.applicationShelfItemSpacing
        let buttonPadding = Appearance.applicationShelfItemPadding
        let rowCount: CGFloat = 2
        let rowHeight = buttonHeight + buttonPadding * 2
        return paddingVertical * 2 + searchFieldHeight + Appearance.panelSectionSpacing + rowHeight * rowCount + rowSpacing * (rowCount - 1)
    }

    private let paddingHorizontal: CGFloat = 18
    private let paddingVertical: CGFloat = 12
    private let searchFieldHeight: CGFloat = 34
    private let buttonSize = NSSize(width: 90, height: 82)
    private var buttonSpacing: CGFloat { Appearance.applicationShelfItemSpacing }
    private var maxVisibleItems: Int { Appearance.applicationShelfItemCount }
    private var itemsPerRow = 1

    let searchField = NSSearchField()
    private let scrollView = NSScrollView(frame: .zero)
    private let contentView = FlippedView(frame: .zero)

    private var items = [ApplicationsCatalogItem]()
    private var filteredItems = [ApplicationsCatalogItem]()
    private var buttons = [ApplicationShelfItemButton]()
    private var selectedIndex: Int?

    var onLaunchRequested: ((ApplicationsCatalogItem) -> Void)?

    var preferredHeight: CGFloat { ApplicationsShelfView.defaultHeight }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        configureSearchField()
        configureScrollView()
        addSubview(searchField)
        addSubview(scrollView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(items: [ApplicationsCatalogItem]) {
        self.items = items
        applyFilter(searchField.stringValue)
    }

    func reset() {
        searchField.stringValue = ""
        applyFilter("")
    }

    func focusSearchField() {
        window?.makeFirstResponder(searchField)
    }

    func moveSelection(offset: Int) {
        guard !filteredItems.isEmpty else { return }
        let current = selectedIndex ?? 0
        var next = current + offset
        next = max(0, min(filteredItems.count - 1, next))
        select(index: next)
    }

    func handleArrowKey(_ direction: Direction) {
        switch direction {
        case .left, .trailing:
            moveSelection(offset: -1)
        case .right, .leading:
            moveSelection(offset: 1)
        case .up:
            moveSelection(offset: -itemsPerRow)
        case .down:
            moveSelection(offset: itemsPerRow)
        }
    }

    func selectFirstMatch() {
        if filteredItems.isEmpty {
            select(index: nil)
        } else {
            select(index: 0)
        }
    }

    func selectedItem() -> ApplicationsCatalogItem? {
        guard let index = selectedIndex, filteredItems.indices.contains(index) else { return nil }
        return filteredItems[index]
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        searchField.frame = NSRect(
            x: paddingHorizontal,
            y: bounds.height - paddingVertical - searchFieldHeight,
            width: width - paddingHorizontal * 2,
            height: searchFieldHeight
        )
        let shelfHeight = max(0, bounds.height - paddingVertical * 2 - searchFieldHeight - Appearance.panelSectionSpacing)
        scrollView.frame = NSRect(
            x: paddingHorizontal,
            y: paddingVertical,
            width: width - paddingHorizontal * 2,
            height: shelfHeight
        )
        layoutButtons()
    }

    private func configureSearchField() {
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 14)
        searchField.placeholderString = NSLocalizedString("Search apps", comment: "Search field placeholder")
        searchField.bezelStyle = .roundedBezel
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true
    }

    private func configureScrollView() {
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.usesPredominantAxisScrolling = true
        scrollView.borderType = .noBorder
        scrollView.documentView = contentView
    }

    private func applyFilter(_ text: String) {
        if text.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { $0.name.localizedCaseInsensitiveContains(text) }
        }
        if filteredItems.count > maxVisibleItems {
            filteredItems = Array(filteredItems.prefix(maxVisibleItems))
        }
        rebuildButtons()
        selectFirstMatch()
    }

    private func rebuildButtons() {
        buttons.forEach { $0.removeFromSuperview() }
        buttons.removeAll(keepingCapacity: true)

        for item in filteredItems {
            let button = ApplicationShelfItemButton(item: item)
            button.target = self
            button.action = #selector(didTapButton(_:))
            contentView.addSubview(button)
            buttons.append(button)
        }
        needsLayout = true
    }

    private func select(index: Int?) {
        selectedIndex = index
        for (idx, button) in buttons.enumerated() {
            if let index = index {
                button.isSelected = idx == index
            } else {
                button.isSelected = false
            }
        }
    }

    private func layoutButtons() {
        let buttonPadding = Appearance.applicationShelfItemPadding
        let effectiveButtonHeight = buttonSize.height + buttonPadding * 2
        let effectiveButtonWidth = buttonSize.width + buttonPadding * 2
        let horizontalStep = effectiveButtonWidth + buttonSpacing
        let availableWidth = max(scrollView.bounds.width, effectiveButtonWidth)
        let columns = max(1, Int((availableWidth + buttonSpacing) / horizontalStep))
        itemsPerRow = columns

        for (index, button) in buttons.enumerated() {
            let row = index / columns
            let column = index % columns
            let x = buttonPadding + CGFloat(column) * horizontalStep
            let y = buttonPadding + CGFloat(row) * (effectiveButtonHeight + buttonSpacing)
            button.frame = NSRect(x: x, y: y, width: buttonSize.width, height: buttonSize.height)
        }

        let rows = max(1, Int(ceil(Double(buttons.count) / Double(columns))))
        let contentWidth = max(
            scrollView.bounds.width,
            CGFloat(columns) * effectiveButtonWidth + CGFloat(max(0, columns - 1)) * buttonSpacing
        )
        let contentHeight = max(
            scrollView.bounds.height,
            CGFloat(rows) * effectiveButtonHeight + CGFloat(max(0, rows - 1)) * buttonSpacing
        )
        contentView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight)
    }

    @objc private func didTapButton(_ sender: ApplicationShelfItemButton) {
        guard let index = buttons.firstIndex(where: { $0 === sender }) else { return }
        select(index: index)
        onLaunchRequested?(sender.item)
    }
}

extension ApplicationsShelfView: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        applyFilter(searchField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveLeft(_:)):
            moveSelection(offset: -1)
            return true
        case #selector(NSResponder.moveRight(_:)):
            moveSelection(offset: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(offset: -itemsPerRow)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(offset: itemsPerRow)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            if let item = selectedItem() {
                onLaunchRequested?(item)
            }
            return true
        default:
            return false
        }
    }
}

private class ApplicationShelfItemButton: NSButton {
    let item: ApplicationsCatalogItem
    var isSelected = false {
        didSet { updateAppearance() }
    }
    private let backgroundLayer = CALayer()
    private let padding = Appearance.applicationShelfItemPadding

    init(item: ApplicationsCatalogItem) {
        self.item = item
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageAbove
        alignment = .center
        font = NSFont.systemFont(ofSize: 12)
        lineBreakMode = .byTruncatingTail
        setButtonType(.momentaryChange)
        image = item.icon
        title = item.name
        focusRingType = .none
        wantsLayer = true
        backgroundLayer.cornerRadius = 8
        layer?.insertSublayer(backgroundLayer, at: 0)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds.insetBy(dx: -padding, dy: -padding)
    }

    private func updateAppearance() {
        if isSelected {
            let highlightColor: NSColor
            if #available(macOS 10.14, *) {
                highlightColor = .selectedContentBackgroundColor
            } else {
                highlightColor = .selectedControlColor
            }
            backgroundLayer.backgroundColor = highlightColor.withAlphaComponent(0.35).cgColor
        } else {
            backgroundLayer.backgroundColor = NSColor.clear.cgColor
        }
    }
}
