import Cocoa
import ShortcutRecorder

class ATShortcut {
    static var lastEventIsARepeat = false
    var shortcut: Shortcut
    var id: String
    var scope: ShortcutScope
    var triggerPhase: ShortcutTriggerPhase
    var state: ShortcutState = .up
    var index: Int?

    init(_ shortcut: Shortcut, _ id: String, _ scope: ShortcutScope, _ triggerPhase: ShortcutTriggerPhase, _ index: Int? = nil) {
        self.shortcut = shortcut
        self.id = id
        self.scope = scope
        self.triggerPhase = triggerPhase
        self.index = index
    }

    func matches(_ id: Int?, _ shortcutState: ShortcutState?, _ keyCode: UInt32?, _ modifiers: NSEvent.ModifierFlags?) -> Bool {
        if processShortcutIdentifier(id: id, shortcutState: shortcutState) {
            return true
        }
        if let modifiers, processModifierMatch(modifiers: modifiers, keyCode: keyCode) {
            return true
        }
        return false
    }

    private func processShortcutIdentifier(id: Int?, shortcutState: ShortcutState?) -> Bool {
        guard let id = id,
              let shortcutState = shortcutState,
              let shortcutId = KeyboardEventsTestable.globalShortcutsIds.first(where: { $0.value == id })?.key,
              shortcutId == self.id else {
            return false
        }
        state = shortcutState
        let isDownTrigger = triggerPhase == .down && state == .down
        let isUpTrigger = triggerPhase == .up && state == .up
        return isDownTrigger || isUpTrigger
    }

    private func processModifierMatch(modifiers: NSEvent.ModifierFlags, keyCode: UInt32?) -> Bool {
        let modifiersAreMatching = modifiersMatch(cocoaToCarbonFlags(modifiers))
        let keysMatch = shortcut.keyCode == .none || keyCode == shortcut.carbonKeyCode
        let newState: ShortcutState = (keysMatch && modifiersAreMatching) ? .down : .up
        let stateChanged = state != newState
        state = newState
        if triggerPhase == .down && state == .down {
            return true
        }
        if triggerPhase == .up && state == .up && stateChanged {
            return true
        }
        return false
    }

    private func modifiersMatch(_ modifiers: UInt32) -> Bool {
        // holdShortcut: contains at least
        if id.hasPrefix("holdShortcut") {
            return modifiers == (modifiers | shortcut.carbonModifierFlags)
        }
        // other shortcuts: contains exactly or exactly + holdShortcut modifiers
        let holdModifiers = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", App.app.shortcutIndex)]?.shortcut.carbonModifierFlags ?? 0
        return modifiers == shortcut.carbonModifierFlags || modifiers == (shortcut.carbonModifierFlags | holdModifiers)
    }

    func shouldTrigger() -> Bool {
        if scope == .global {
            if triggerPhase == .down {
                let indexMatches = index == nil || index == App.app.shortcutIndex
                return !App.app.appIsBeingUsed || indexMatches
            }
            // Handle new holdShortcutRelease actions
            if triggerPhase == .up && id.hasSuffix("Release") {
                let indexMatches = index == nil || index == App.app.shortcutIndex
                return App.app.appIsBeingUsed && indexMatches
            }
            // Handle legacy behavior for other .up shortcuts
            if triggerPhase == .up {
                let indexMatches = index == nil || index == App.app.shortcutIndex
                let shouldFocusOnRelease = Preferences.shortcutStyle[App.app.shortcutIndex] == .focusOnRelease
                return App.app.appIsBeingUsed && indexMatches && !App.app.forceDoNothingOnRelease && shouldFocusOnRelease
            }
        }
        if scope == .local {
            let indexMatches = index == nil || index == App.app.shortcutIndex
            return App.app.appIsBeingUsed && indexMatches
        }
        return false
    }

    func executeAction(_ isARepeat: Bool) {
        Logger.info("executeAction", id)
        ATShortcut.lastEventIsARepeat = isARepeat
        ControlsTab.executeAction(id)
    }

    /// keyboard events can be unreliable. They can arrive in the wrong order, or may never arrive
    /// this function acts as a safety net to improve the chances that some keyUp behaviors are enforced
    func redundantSafetyMeasures() {
        // Keyboard shortcuts come from different sources. As a result, they can arrive in the wrong order (e.g. alt DOWN > alt UP > alt+tab DOWN > alt+tab UP)
        // The events can be disordered between sources, but not within each source
        // Another issue is events being dropped by macOS, which we never receive
        // Knowing this, we handle these edge-cases by double checking if holdShortcut is UP, when any shortcut state is UP
        // If it is, then we trigger the holdShortcut release action
        if App.app.appIsBeingUsed {
            // Check for new holdShortcutRelease shortcuts
            if let releaseShortcut = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", App.app.shortcutIndex) + "Release"],
               id == releaseShortcut.id || id.hasPrefix("holdShortcut") {
                let currentModifiers = cocoaToCarbonFlags(ModifierFlags.current)
                let holdShortcutId = Preferences.indexToName("holdShortcut", App.app.shortcutIndex)
                if let currentHoldShortcut = ControlsTab.shortcuts[holdShortcutId] {
                    if currentModifiers != (currentModifiers | (currentHoldShortcut.shortcut.carbonModifierFlags)) {
                        currentHoldShortcut.state = .up
                        ControlsTab.executeAction(holdShortcutId + "Release")
                    }
                }
            }
            // Handle legacy behavior
            if !App.app.forceDoNothingOnRelease && Preferences.shortcutStyle[App.app.shortcutIndex] == .focusOnRelease {
                if let currentHoldShortcut = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", App.app.shortcutIndex)],
                   id == currentHoldShortcut.id {
                    let currentModifiers = cocoaToCarbonFlags(ModifierFlags.current)
                    if currentModifiers != (currentModifiers | (currentHoldShortcut.shortcut.carbonModifierFlags)) {
                        currentHoldShortcut.state = .up
                        ControlsTab.executeAction(currentHoldShortcut.id)
                    }
                }
            }
        }
        if state == .up {
            // ensure timers don't keep running if their shortcut is UP
            KeyRepeatTimer.deactivateTimerForRepeatingKey(id)
        }
    }
}

enum ShortcutTriggerPhase {
    case down
    case up
}

enum ShortcutState {
    case down
    case up
}

enum ShortcutScope {
    case global
    case local
}
