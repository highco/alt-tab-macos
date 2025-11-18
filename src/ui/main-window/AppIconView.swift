import Cocoa

class AppIconView: NSView {
    var app: InstalledApp?
    var iconView = NSImageView()
    var label = NSTextField()
    var isFocused = false
    var isHovered = false
    var launchCallback: ((InstalledApp) -> Void)?
    
    static let iconSize: CGFloat = 64
    static let cellWidth: CGFloat = 100
    static let cellHeight: CGFloat = 100 // Increased to prevent label cutoff
    
    init() {
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 14 // More rounded corners for modern look
        
        // Setup icon view
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.wantsLayer = true
        addSubview(iconView)
        
        // Setup label
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.textColor = Appearance.fontColor
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        
        // Layout constraints with better spacing
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            iconView.widthAnchor.constraint(equalToConstant: AppIconView.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: AppIconView.iconSize),
            
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6)
        ])
        
        // Enable mouse tracking
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    func updateWithApp(_ app: InstalledApp) {
        self.app = app
        if let cgImage = app.icon {
            iconView.image = NSImage(cgImage: cgImage, size: NSSize(width: AppIconView.iconSize, height: AppIconView.iconSize))
        }
        label.stringValue = app.name
    }
    
    func drawHighlight() {
        // Animate the highlight changes for smooth transitions
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.15)
        
        if isFocused {
            layer?.backgroundColor = Appearance.highlightFocusedBackgroundColor.cgColor
            layer?.borderColor = Appearance.highlightFocusedBorderColor.cgColor
            layer?.borderWidth = 2.5
            
            // Add subtle shadow when focused
            layer?.shadowColor = Appearance.highlightFocusedBorderColor.cgColor
            layer?.shadowOpacity = 0.3
            layer?.shadowOffset = NSSize(width: 0, height: 0)
            layer?.shadowRadius = 6
        } else if isHovered {
            layer?.backgroundColor = Appearance.highlightHoveredBackgroundColor.cgColor
            layer?.borderColor = Appearance.highlightHoveredBorderColor.cgColor
            layer?.borderWidth = 2
            
            // Lighter shadow when hovered
            layer?.shadowColor = Appearance.highlightHoveredBorderColor.cgColor
            layer?.shadowOpacity = 0.2
            layer?.shadowOffset = NSSize(width: 0, height: 0)
            layer?.shadowRadius = 4
        } else {
            layer?.backgroundColor = .clear
            layer?.borderWidth = 0
            layer?.shadowOpacity = 0
        }
        
        CATransaction.commit()
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        drawHighlight()
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        drawHighlight()
    }
    
    override func mouseUp(with event: NSEvent) {
        if let app = app {
            launchCallback?(app)
        }
    }
}

