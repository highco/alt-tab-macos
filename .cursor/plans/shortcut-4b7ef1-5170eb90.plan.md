<!-- 5170eb90-66b1-431c-9971-8c56064dba49 b16c0fdf-9692-4534-9693-dd09d2d1e590 -->
# Shortcut Mode Refactor Plan

## Summary

Implement an explicit “app vs window” mode tracked by `App` and used by `ThumbnailsPanel`/`ThumbnailsView` so keyboard shortcuts respond as requested. Showing the UI via a hold shortcut always starts in app mode (search focused); cycling windows via next-window shortcuts switches to window mode; interactions inside the apps section bring the UI back to app mode. Releasing the hold shortcut will honor both the current mode and the existing shortcut style preference.

## Steps

1. **Define Mode State (`setup-mode-state`)**

- Add an `enum MainWindowMode { case app, window }` and a stored property (likely on `App` or `ThumbnailsPanel`) plus helpers to toggle/query the current mode.
- Ensure the mode defaults to `.app` whenever the UI is shown and expose a method the UI elements can call to switch modes.

2. **Hook Show/Cycle Actions (`wire-shortcut-transitions`)**

- Update `App.showUiOrCycleSelection` and related shortcut actions in `ControlsTab.shortcutsActions` so: hold shortcut down shows the UI in app mode with `ThumbnailsPanel.applicationsShelfView` search focused immediately; next-window shortcuts call a helper that switches to window mode before cycling.
- Make sure repeated `nextWindowShortcut` presses keep the UI in window mode.

3. **App Section Interactions (`apps-section-mode`)**

- In `ApplicationsShelfView` (search field delegate and selection changes) and any app-icon selection logic, call the helper to switch back to app mode; ensure `ThumbnailsView` highlights/rows stay untouched while in app mode.

4. **Hold Release Behavior (`release-behavior`)**

- Adjust `App.focusTarget` / shortcut action invoked on hold release so it checks both the shortcut-style preference and the current mode: if in app mode, simply keep the UI visible regardless of style; if in window mode and style is `focusOnRelease`, focus the selected window and hide UI; if style is `doNothingOnRelease`, still do nothing.
- Keep `forceDoNothingOnRelease` semantics intact for other flows.

5. **Update UI Glue & Tests (`ui-glue-tests`)**

- Ensure `ThumbnailsPanel.show()` still focuses search field but now also explicitly sets mode.
- Add any necessary unit coverage in existing shortcut tests (e.g., `KeyboardEventsTests` or new logic tests) to assert the new mode transitions if feasible.

### To-dos

- [ ] Add app/window mode state + helper APIs
- [ ] Switch mode on hold show and next-window shortcuts
- [ ] Return to app mode on search focus/app selection
- [ ] Respect mode + shortcut style on hold release
- [ ] Adjust panel/search glue + add tests