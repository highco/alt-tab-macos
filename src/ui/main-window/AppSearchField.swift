import Cocoa

class AppSearchField: NSTextField {
    var onTextChange: ((String) -> Void)?
    
    init() {
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        placeholderString = "Search applications..."
        isBordered = false
        backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.1)
        textColor = Appearance.fontColor
        font = Appearance.font
        focusRingType = .none
        drawsBackground = true
        wantsLayer = true
        layer?.cornerRadius = 8
        delegate = self
        
        // Make it behave like a search field
        if let cell = cell as? NSTextFieldCell {
            cell.usesSingleLineMode = true
            cell.wraps = false
            cell.isScrollable = true
        }
    }
    
    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onTextChange?(stringValue)
    }
    
    func clear() {
        stringValue = ""
        onTextChange?("")
    }
}

extension AppSearchField: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Allow certain keys to be handled by the text field
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // Enter key - let the app handle it for launching
            return false
        } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Escape key - clear field or let app handle hiding
            if !stringValue.isEmpty {
                clear()
                return true
            }
            return false
        } else if commandSelector == #selector(NSResponder.deleteBackward(_:)) {
            // Backspace - let text field handle it
            return false
        } else if commandSelector == #selector(NSResponder.moveUp(_:)) ||
                  commandSelector == #selector(NSResponder.moveDown(_:)) ||
                  commandSelector == #selector(NSResponder.moveLeft(_:)) ||
                  commandSelector == #selector(NSResponder.moveRight(_:)) {
            // Arrow keys - let app handle navigation
            return false
        }
        return false
    }
}

