# Main Window Code Documentation

## General Overview

The main window module (`src/ui/main-window/`) is responsible for rendering and managing the Alt+Tab switcher interface. This is the core UI component that displays when users press the Alt+Tab keyboard shortcut. The module consists of several interconnected components that work together to create a fluid, responsive window switching experience.

### Architecture

The main window follows a hierarchical structure:

1. **ThumbnailsPanel** - The top-level window panel that contains everything
2. **ThumbnailsView** - Manages the layout and scrolling of thumbnail views
3. **ThumbnailView** - Individual cell representing a window/application
4. **PreviewPanel** - Shows a larger preview of the currently focused window
5. **Supporting Views** - Various UI components for icons, labels, and indicators

### Key Features

- **Three Display Styles**: Thumbnails, App Icons, and Titles-only modes
- **View Recycling**: Efficiently reuses view instances to handle many windows
- **Responsive Layout**: Automatically arranges thumbnails in rows based on available space
- **Drag and Drop**: Supports dropping files/URLs onto thumbnails to open with that app
- **Accessibility**: Full VoiceOver support and keyboard navigation
- **Visual Effects**: Supports both traditional frosted glass and macOS 26+ liquid glass effects
- **Multi-monitor & Multi-space**: Handles complex display and space configurations

---

## File-by-File Breakdown

### ThumbnailsPanel.swift

The top-level window container that hosts the entire switcher interface.

#### Class: `ThumbnailsPanel`

**Purpose**: An `NSPanel` subclass that serves as the main window for the Alt+Tab switcher. It's configured to appear above all other windows (except system dialogs) and work across all Spaces.

**Key Properties**:
- `thumbnailsView: ThumbnailsView` - The main content view managing all thumbnails

**Important Methods**:

```swift
convenience init()
```
- Initializes the panel with non-activating style (doesn't steal focus)
- Sets window level to `.popUpMenu` (2nd highest, allows appearing above context menus)
- Configures the panel to join all Spaces
- Sets up accessibility properties

```swift
func updateAppearance()
```
- Updates the panel's shadow and appearance theme based on user preferences
- Switches between dark and light themes dynamically

```swift
func updateContents()
```
- Main method called to refresh the entire switcher UI
- Uses `CATransaction` to disable animations during layout updates
- Updates thumbnail layout, resizes the panel, and repositions it on screen
- Includes safety checks to abort if the app is no longer being used

```swift
func show()
```
- Makes the panel visible and key
- Enables mouse event tracking
- Flashes scrollbars to indicate scrollable content

```swift
static func maxThumbnailsWidth() -> CGFloat
```
- Calculates the maximum width available for thumbnails
- For "titles" style, considers comfortable readability width
- For other styles, uses a percentage of screen width

```swift
static func maxThumbnailsHeight() -> CGFloat
```
- Calculates maximum height as a percentage of screen height

**Window Delegate Extension**:
- `windowDidResignKey(_:)` - Ensures the panel maintains key focus when active, preventing other windows from stealing focus

---

### ThumbnailsView.swift

Manages the collection of thumbnail views, their layout, and scrolling behavior.

#### Class: `ThumbnailsView`

**Purpose**: Coordinates the layout and display of all thumbnail views. Handles view recycling, row management, and navigation between thumbnails.

**Key Properties**:
- `scrollView: ScrollView` - Custom scroll view containing thumbnails
- `contentView: EffectView` - The background effect view (frosted/liquid glass)
- `recycledViews: [ThumbnailView]` - Pool of reusable thumbnail views (pre-allocated for performance)
- `rows: [[ThumbnailView]]` - Two-dimensional array organizing thumbnails into rows
- `thumbnailsWidth/Height: CGFloat` - Cached dimensions of the thumbnail area

**Important Methods**:

```swift
func updateItemsAndLayout()
```
- Main entry point for updating the entire thumbnail layout
- Calculates optimal layout, positions all views, centers rows if needed
- Sets up row metadata (first/last in row, index, count)

```swift
private func layoutThumbnailViews(_ widthMax: CGFloat) -> (CGFloat, CGFloat, CGFloat)?
```
- Core layout algorithm that arranges thumbnails in rows
- Handles both left-to-right and right-to-left layouts
- Wraps to new rows when thumbnails exceed available width
- Returns maximum X, maximum Y, and label height

```swift
func navigateUpOrDown(_ direction: Direction, allowWrap: Bool)
```
- Handles vertical navigation (up/down arrow keys)
- Finds the closest thumbnail in the target row based on horizontal position
- Respects layout direction (LTR/RTL) for proper navigation

```swift
func nextRow(_ direction: Direction, allowWrap: Bool) -> [ThumbnailView]?
```
- Determines the next row in the given direction
- Supports wrapping (cycling from last to first row)
- Prevents wrapping during key repeat to avoid infinite loops

```swift
func centerRows(_ maxX: CGFloat)
```
- Centers rows when `Preferences.alignThumbnails == .center`
- Calculates row widths and shifts thumbnails horizontally to center them

```swift
func reset()
```
- Resets all views when appearance settings change
- Recreates the background effect view
- Reinitializes all recycled views

#### Class: `ScrollView`

**Purpose**: Custom `NSScrollView` with enhanced mouse tracking and scroll behavior.

**Key Features**:
- Responsive scrolling enabled
- Mouse tracking for hover effects
- Prevents hover updates during scrolling to avoid jank

**Important Methods**:

```swift
override func mouseMoved(with event: NSEvent)
```
- Tracks mouse movement to update hover state
- Finds the thumbnail view under the cursor
- Disables hover during active scrolling

```swift
override func scrollWheel(with event: NSEvent)
```
- Custom scroll handling
- Forces shift+scroll to be vertical (prevents horizontal scrolling when shift is part of shortcuts)

#### Class: `FlippedView`

**Purpose**: Simple `NSView` subclass with flipped coordinate system (origin at top-left instead of bottom-left).

#### Enum: `Direction`

**Purpose**: Represents navigation directions (left, right, leading, trailing, up, down) with support for RTL layouts.

---

### ThumbnailView.swift

The individual cell view representing a single window or application.

#### Class: `ThumbnailView`

**Purpose**: A reusable view that displays one window's thumbnail, icon, title, and various indicators. This is the most complex component, handling all visual aspects of a single window entry.

**Key Properties**:
- `window_: Window?` - The window data being displayed
- `thumbnail: LightImageView` - The window screenshot thumbnail
- `appIcon: LightImageView` - The application icon
- `label: ThumbnailTitleView` - The window/app title text
- `windowControlIcons: [TrafficLightButton]` - Close, minimize, maximize, quit buttons
- `windowIndicatorIcons: [ThumbnailFontIconView]` - Status indicators (hidden, fullscreen, minimized, space)
- `dockLabelIcon: ThumbnailFilledFontIconView` - Red badge showing dock notification count
- `mouseUpCallback/mouseMovedCallback: (() -> Void)!` - Callbacks for user interactions

**Important Methods**:

```swift
func updateRecycledCellWithNewContent(_ element: Window, _ index: Int, _ newHeight: CGFloat)
```
- Main method to update a recycled view with new window data
- Updates all visual elements, sizes, and positions
- Sets up tooltips and callbacks

```swift
func drawHighlight()
```
- Updates the visual highlight state (focused/hovered)
- Changes background color and border based on selection state
- Handles special label display logic for app-icons style

```swift
func showOrHideWindowControls(_ shouldShowWindowControls: Bool)
```
- Shows/hides the traffic light buttons (close, minimize, etc.)
- Respects user preferences and window capabilities
- Forces redraw to update button states

```swift
private func updateValues(_ element: Window, _ index: Int, _ newHeight: CGFloat)
```
- Updates all visual elements based on window data
- Shows/hides indicators based on window state (minimized, fullscreen, hidden, space)
- Updates thumbnail image or falls back to app icon
- Configures title text based on user preferences
- Sets up accessibility labels

```swift
private func updateSizes(_ newHeight: CGFloat)
```
- Calculates and sets frame sizes for the view and all subviews
- Handles different sizing logic for each appearance style
- Sets label width based on available space

```swift
private func updatePositions(_ newHeight: CGFloat)
```
- Positions all subviews within the thumbnail view
- Handles RTL layout direction
- Positions window control buttons in a grid pattern
- Calculates dock label badge position (complex due to NSTextField quirks)

```swift
private func updateAppIconsLabelFrame(_ view: ThumbnailView)
```
- Complex logic for positioning labels in app-icons style
- Allows labels to extend beyond thumbnail bounds into adjacent cells
- Calculates available space on left/right sides
- Handles edge cases (first/last in row, single item in row)

**Mouse Interaction Methods**:

```swift
override func mouseUp(with event: NSEvent)
```
- Handles click to focus the selected window

```swift
override func otherMouseUp(with event: NSEvent)
```
- Handles middle-click to close window or quit app

```swift
func mouseMoved()
```
- Shows window controls on hover
- Triggers hover callback

**Drag and Drop Methods**:

```swift
override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation
```
- Initiates drag-and-drop handling
- Sets up a timer for auto-selection after 2 seconds

```swift
override func performDragOperation(_ sender: NSDraggingInfo) -> Bool
```
- Opens dragged files/URLs with the target application
- Hides the UI after successful drop

**Static Helper Methods**:

```swift
static func thumbnailSize(_ image: CGImage?, _ isWindowlessApp: Bool) -> NSSize
```
- Calculates optimal thumbnail size maintaining aspect ratio
- Respects maximum dimensions
- Preserves 1:1 ratio for very small windows

```swift
static func iconSize() -> NSSize
```
- Returns app icon size based on appearance style and preferences

```swift
static func height(_ labelHeight: CGFloat) -> CGFloat
```
- Calculates total thumbnail height based on style and label height

```swift
static func maxThumbnailWidth() -> CGFloat
```
- Returns maximum width for a single thumbnail

```swift
static func minThumbnailWidth() -> CGFloat
```
- Returns minimum width for a single thumbnail

---

### PreviewPanel.swift

Displays a larger preview of the currently focused window.

#### Class: `PreviewPanel`

**Purpose**: A floating panel that shows an enlarged preview of the window the user is currently hovering over or has selected. Appears below the thumbnails panel.

**Key Properties**:
- `previewView: LightImageView` - The image view displaying the preview
- `borderView: BorderView` - A border overlay indicating selection
- `currentId: CGWindowID?` - The window ID currently being previewed

**Important Methods**:

```swift
override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect
```
- Overrides default constraint to allow the panel to appear above the menubar
- Returns the frame unmodified

```swift
func show(_ id: CGWindowID, _ preview: CGImage, _ position: CGPoint, _ size: CGSize)
```
- Shows the preview panel with a specific window's preview
- Converts coordinates from Quartz (bottom-left origin) to Cocoa (top-left origin)
- Handles fade-in animation if enabled
- Sets window level below thumbnails panel to ensure proper z-ordering

```swift
func updateImageIfShowing(_ id: CGWindowID?, _ preview: CGImage, _ size: CGSize)
```
- Updates the preview image if the panel is visible and showing the same window
- Optimized to avoid unnecessary updates

#### Class: `BorderView`

**Purpose**: A custom view that draws a rounded border around the preview using the system accent color.

---

### ThumbnailTitleView.swift

A specialized text field for displaying window/app titles.

#### Class: `ThumbnailTitleView`

**Purpose**: Extends `NSTextField` with custom truncation behavior and sizing logic.

**Important Methods**:

```swift
func fixHeight()
```
- Sets a fixed height constraint based on the text's natural height

```swift
func setWidth(_ width: CGFloat)
```
- Sets the width, handling NSTextField's internal constraint quirks
- Removes existing width constraints before adding a new one
- Workaround for NSTextField constraint issues

```swift
func updateTruncationModeIfNeeded()
```
- Updates the line break mode based on user preferences
- Supports truncating at start, middle, or end

```swift
override func mouseMoved(with event: NSEvent)
```
- Prevents tooltips from disappearing on mouse movement
- Empty implementation blocks default behavior

---

### ThumbnailFontIconView.swift

Displays SF Symbols as status indicators.

#### Enum: `Symbols`

**Purpose**: Defines SF Symbol characters used for various indicators:
- `circledPlusSign` - Fullscreen indicator
- `circledMinusSign` - Minimized indicator
- `circledSlashSign` - Hidden app indicator
- `circledNumber0-10` - Space numbers
- `circledStar` - All spaces indicator
- And more...

#### Class: `ThumbnailFontIconView`

**Purpose**: Displays SF Symbols with proper formatting and sizing.

**Important Methods**:

```swift
func setNumber(_ number: Int, _ filled: Bool)
```
- Sets the icon to display a specific number (0-50)
- Supports both filled and unfilled circle variants
- Uses Unicode math to calculate the correct symbol

```swift
func setStar() / setFilledStar()
```
- Sets the icon to display a star (for "all spaces" indicator)

#### Class: `ThumbnailFilledFontIconView`

**Purpose**: A composite view that displays a font icon on top of a colored background circle (used for dock badges).

---

### ThumbnailsPanelBackgroundView.swift

Manages the visual effect background (frosted glass or liquid glass).

#### Protocol: `EffectView`

**Purpose**: Common interface for different background effect implementations.

#### Class: `LiquidGlassEffectView` (macOS 26+)

**Purpose**: Uses the new `NSGlassEffectView` API for a modern liquid glass appearance.

**Important Methods**:

```swift
static func canUsePrivateLiquidGlassLook() -> Bool
```
- Checks if the private `set_variant:` API is available
- Uses runtime introspection to detect API availability

```swift
func safeSetVariant(_ value: Int)
```
- Safely calls the private `set_variant:` method using runtime reflection
- Handles cases where the API might not be available

#### Class: `FrostedGlassEffectView`

**Purpose**: Traditional `NSVisualEffectView` implementation for older macOS versions.

**Important Methods**:

```swift
private func updateRoundedCorners(_ cornerRadius: CGFloat)
```
- Creates smooth rounded corners using a mask image
- More accurate than `layer.cornerRadius` which causes aliasing
- Uses a stretchable mask image for performance

#### Function: `makeAppropriateEffectView() -> EffectView`

**Purpose**: Factory function that selects the appropriate effect view based on:
- macOS version (26+ for liquid glass)
- Appearance style (app-icons uses liquid glass if available)
- API availability

---

## Key Design Patterns

### View Recycling

The codebase uses view recycling to efficiently handle many windows. A pool of 20 `ThumbnailView` instances is pre-allocated and reused. When windows change, views are updated with new content rather than creating new views. This provides:
- Better performance with many windows
- Smooth animations
- Lower memory usage

### Coordinate System Handling

The code carefully handles coordinate system conversions:
- Quartz uses bottom-left origin (used for window positions)
- Cocoa uses top-left origin (used for views)
- `FlippedView` flips the coordinate system for easier layout
- RTL (right-to-left) languages are fully supported

### Layout Algorithm

The layout system:
1. Calculates available space based on screen size and preferences
2. Determines optimal thumbnail sizes
3. Arranges thumbnails in rows, wrapping when needed
4. Centers rows if requested
5. Handles both LTR and RTL layouts

### State Management

The UI tracks multiple states:
- **Focused**: The window that will be activated on release
- **Hovered**: The window under the mouse cursor
- **Selected**: The window that was clicked

These states are managed globally through `Windows.focusedWindowIndex` and `Windows.hoveredWindowIndex`.

---

## Integration Points

### With Logic Layer

- **`Window`**: Provides window data (title, thumbnail, icon, state)
- **`Windows`**: Manages the list of windows and selection state
- **`Appearance`**: Provides all styling and sizing constants
- **`Preferences`**: User preferences affecting display and behavior

### With App Layer

- **`App.app.thumbnailsPanel`**: Main entry point for showing/hiding UI
- **`App.app.previewPanel`**: Preview panel instance
- **`App.app.hideUi()`**: Called to dismiss the switcher

### With Event System

- **`MouseEvents`**: Tracks mouse movement and clicks
- **`KeyboardEvents`**: Handles keyboard navigation
- **`ATShortcut`**: Manages keyboard shortcuts

---

## Performance Considerations

1. **View Recycling**: Prevents allocation/deallocation overhead
2. **CATransaction**: Disables animations during bulk updates
3. **Lazy Image Loading**: Thumbnails are loaded asynchronously
4. **Efficient Layout**: Single-pass layout algorithm
5. **Conditional Updates**: Only updates visible/changed elements

---

## Accessibility

The codebase includes comprehensive accessibility support:

- **VoiceOver**: All views have proper accessibility labels
- **Keyboard Navigation**: Full keyboard support for navigation
- **Screen Reader**: Descriptive text for all UI elements
- **Focus Management**: Proper focus handling for keyboard users

---

## Localization

The UI supports:
- **RTL Languages**: Complete right-to-left layout support
- **Text Truncation**: Handles varying text lengths across languages
- **Localized Strings**: All user-facing text is localized
- **Layout Direction**: Respects system layout direction preferences

