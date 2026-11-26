import AppKit
import AtacCore

// MARK: - Custom Non-Activating Key Panel

private final class HistoryPanel: NSPanel {
    var onMoveSelection: ((Int) -> Void)?
    var onConfirmSelection: ((Bool) -> Void)?
    var onCopyOnlySelected: (() -> Void)?
    var onRevealSelectedInFinder: (() -> Void)?
    var onQuickSelect: ((Int) -> Void)?
    var onTogglePin: (() -> Void)?
    var onDeleteSelected: (() -> Void)?
    var onClearUnpinned: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCmd = flags.contains(.command)
            let isOpt = flags.contains(.option)
            let isCtrl = flags.contains(.control)
            let isShift = flags.contains(.shift)

            switch event.keyCode {
            case 53: // Escape
                onEscape?()
                return
            case 125: // Down Arrow
                onMoveSelection?(1)
                return
            case 126: // Up Arrow
                onMoveSelection?(-1)
                return
            case 45 where isCtrl && !isCmd && !isOpt: // Ctrl+N
                onMoveSelection?(1)
                return
            case 35 where isCtrl && !isCmd && !isOpt: // Ctrl+P
                onMoveSelection?(-1)
                return
            case 36, 76: // Return / Keypad Enter
                onConfirmSelection?(isOpt)
                return
            case 35 where (isOpt || isCmd) && !isCtrl: // Opt+P or Cmd+P -> Pin
                onTogglePin?()
                return
            case 15 where isCmd && !isOpt && !isCtrl: // Cmd+R -> Reveal in Finder
                onRevealSelectedInFinder?()
                return
            case 8 where isCmd && !isOpt && !isCtrl: // Cmd+C -> Copy item directly
                if let editor = firstResponder as? NSTextView, editor.selectedRange().length > 0 {
                    break
                }
                onCopyOnlySelected?()
                return
            case 51 where isCmd && isShift: // Shift+Cmd+Delete -> Clear unpinned
                onClearUnpinned?()
                return
            case 51 where isOpt: // Opt+Delete -> Delete selected item
                onDeleteSelected?()
                return
            case 117: // Forward Delete (fn+Delete) -> Delete selected item
                onDeleteSelected?()
                return
            default:
                break
            }

            if isCmd && !isOpt && !isCtrl {
                if let chars = event.charactersIgnoringModifiers, chars.count == 1, let ch = chars.first {
                    if let digit = ch.wholeNumberValue, (1...9).contains(digit) {
                        onQuickSelect?(digit - 1)
                        return
                    }
                    if ch == "," {
                        onOpenSettings?()
                        return
                    }
                    if ch == "q" {
                        NSApp.terminate(nil)
                        return
                    }
                }
            }
        }
        super.sendEvent(event)
    }
}

// MARK: - Hover-Tracking NSTableView (Blue Selection Follows Mouse Cursor)

private final class HoverTableView: NSTableView {
    private var trackingAreaRef: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverSelection(windowPoint: event.locationInWindow)
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoverSelection(windowPoint: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        if selectedRow != -1 {
            deselectAll(nil)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        updateHoverSelection(windowPoint: event.locationInWindow)
    }

    func syncHoverToCurrentMouse() {
        guard let win = window else { return }
        let screenPt = NSEvent.mouseLocation
        let winPt = win.convertPoint(fromScreen: screenPt)
        let localPt = convert(winPt, from: nil)
        if visibleRect.contains(localPt) {
            updateHoverSelection(windowPoint: winPt)
        } else if selectedRow != -1 {
            deselectAll(nil)
        }
    }

    private func updateHoverSelection(windowPoint: NSPoint) {
        let pt = convert(windowPoint, from: nil)
        guard visibleRect.insetBy(dx: 4, dy: 0).contains(pt) else {
            if selectedRow != -1 {
                deselectAll(nil)
            }
            return
        }
        let hoveredRow = row(at: pt)
        if hoveredRow >= 0 && hoveredRow < numberOfRows {
            if selectedRow != hoveredRow {
                selectRowIndexes(IndexSet(integer: hoveredRow), byExtendingSelection: false)
            }
        } else if selectedRow != -1 {
            deselectAll(nil)
        }
    }
}

// MARK: - Hover Footer Button With Pill Highlight & Soft Shadow

private final class HoverFooterButton: NSControl {
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private var trackingAreaRef: NSTrackingArea?

    private var isHovered = false {
        didSet {
            if oldValue != isHovered {
                updateAppearance()
                needsDisplay = true
            }
        }
    }

    private var isPressed = false {
        didSet {
            if oldValue != isPressed {
                needsDisplay = true
            }
        }
    }

    init(title: String, symbolName: String, target: AnyObject?, action: Selector) {
        super.init(frame: .zero)
        self.target = target
        self.action = action

        iconView.imageScaling = .scaleProportionallyDown
        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: title) {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: 11.5, weight: .medium))
        }

        titleField.stringValue = title
        titleField.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        titleField.drawsBackground = false
        titleField.isBezeled = false
        titleField.isEditable = false
        titleField.isSelectable = false

        addSubview(iconView)
        addSubview(titleField)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaRef {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        // Track until mouseUp cleanly
        guard let win = window else {
            isPressed = false
            return
        }
        var keepTracking = true
        while keepTracking {
            guard let next = win.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) else { break }
            let local = convert(next.locationInWindow, from: nil)
            let inside = bounds.insetBy(dx: -2, dy: -2).contains(local)
            switch next.type {
            case .leftMouseDragged:
                isPressed = inside
                isHovered = inside
            case .leftMouseUp:
                let shouldFire = inside
                isPressed = false
                isHovered = inside
                keepTracking = false
                if shouldFire, let action = self.action {
                    NSApp.sendAction(action, to: self.target, from: self)
                }
            default:
                break
            }
        }
    }

    func refreshHoverFromMouseLocation() {
        guard let win = window else {
            isHovered = false
            isPressed = false
            return
        }
        let winPt = win.convertPoint(fromScreen: NSEvent.mouseLocation)
        let localPt = convert(winPt, from: nil)
        isHovered = bounds.contains(localPt)
        isPressed = false
    }

    private func updateAppearance() {
        let tint: NSColor = isHovered ? .labelColor : .secondaryLabelColor
        titleField.textColor = tint
        iconView.contentTintColor = tint
    }

    override func layout() {
        super.layout()
        titleField.sizeToFit()
        let iconSize: CGFloat = 13
        let spacing: CGFloat = 5
        let totalContentW = iconSize + spacing + titleField.frame.width
        let startX = max(8, floor((bounds.width - totalContentW) * 0.5))

        iconView.frame = NSRect(
            x: startX,
            y: floor((bounds.height - iconSize) * 0.5),
            width: iconSize,
            height: iconSize
        )
        titleField.frame = NSRect(
            x: startX + iconSize + spacing,
            y: floor((bounds.height - titleField.frame.height) * 0.5),
            width: titleField.frame.width,
            height: titleField.frame.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        guard isHovered || isPressed else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let pillRect = bounds.insetBy(dx: 2, dy: 1.5)
        let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 6.5, yRadius: 6.5)

        // Subtle soft drop shadow under hovered button
        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -1.5)
        shadow.shadowBlurRadius = 4.5
        shadow.shadowColor = NSColor.black.withAlphaComponent(isPressed ? 0.34 : 0.26)
        shadow.set()

        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fillAlpha: CGFloat = isPressed ? (isDark ? 0.22 : 0.16) : (isDark ? 0.14 : 0.09)
        let baseColor: NSColor = isDark ? .white : .black
        baseColor.withAlphaComponent(fillAlpha).setFill()
        pillPath.fill()

        // Clear shadow before drawing crisp subtle rim highlight
        NSShadow().set()
        let borderColor = (isDark ? NSColor.white : NSColor.black).withAlphaComponent(isDark ? 0.16 : 0.10)
        borderColor.setStroke()
        pillPath.lineWidth = 0.75
        pillPath.stroke()
    }
}

// MARK: - Symmetrical Table Row & Cell (Soft Shadow on Hovered/Selected Row)

private final class RoundedSelectionRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        let inset = NSRect(
            x: 8,
            y: 1.5,
            width: max(0, bounds.width - 16),
            height: max(0, bounds.height - 3)
        )
        let path = NSBezierPath(roundedRect: inset, xRadius: 6.5, yRadius: 6.5)

        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 3.5
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.24)
        shadow.set()

        NSColor.selectedContentBackgroundColor.setFill()
        path.fill()
    }
}

private final class HistoryCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("HistoryCell")

    private let kindIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutLabel = NSTextField(labelWithString: "")

    private var isPinnedItem = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        kindIconView.imageScaling = .scaleProportionallyDown

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        titleLabel.isEditable = false

        shortcutLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        shortcutLabel.alignment = .right
        shortcutLabel.drawsBackground = false
        shortcutLabel.isBezeled = false
        shortcutLabel.isEditable = false

        addSubview(kindIconView)
        addSubview(titleLabel)
        addSubview(shortcutLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: ClipboardItem, index: Int) {
        isPinnedItem = item.isPinned
        titleLabel.stringValue = item.preview

        let symbolName: String
        if item.isPinned {
            symbolName = "pin.fill"
        } else {
            switch item.kind {
            case .text: symbolName = "text.alignleft"
            case .url: symbolName = "link"
            case .file: symbolName = "doc"
            case .image: symbolName = "photo"
            }
        }

        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 12, weight: item.isPinned ? .semibold : .regular)
            kindIconView.image = img.withSymbolConfiguration(config)
        }

        if index < 9 {
            shortcutLabel.stringValue = "⌘\(index + 1)"
            shortcutLabel.isHidden = false
        } else {
            shortcutLabel.stringValue = ""
            shortcutLabel.isHidden = true
        }

        updateColors(selected: backgroundStyle == .emphasized)
        needsLayout = true
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateColors(selected: backgroundStyle == .emphasized)
        }
    }

    private func updateColors(selected: Bool) {
        if selected {
            titleLabel.textColor = .alternateSelectedControlTextColor
            shortcutLabel.textColor = .alternateSelectedControlTextColor.withAlphaComponent(0.85)
            kindIconView.contentTintColor = .alternateSelectedControlTextColor
        } else {
            titleLabel.textColor = .labelColor
            shortcutLabel.textColor = .tertiaryLabelColor
            kindIconView.contentTintColor = isPinnedItem ? .systemOrange : .secondaryLabelColor
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let w = bounds.width

        let iconSize: CGFloat = 15
        let horizontalPad: CGFloat = 16
        let badgeWidth: CGFloat = shortcutLabel.isHidden ? 0 : 28

        kindIconView.frame = NSRect(
            x: horizontalPad,
            y: floor((h - iconSize) * 0.5),
            width: iconSize,
            height: iconSize
        )

        if !shortcutLabel.isHidden {
            shortcutLabel.frame = NSRect(
                x: w - horizontalPad - badgeWidth,
                y: floor((h - 16) * 0.5),
                width: badgeWidth,
                height: 16
            )
        }

        let titleX = horizontalPad + iconSize + 7
        let rightReserved = horizontalPad + (badgeWidth > 0 ? badgeWidth + 8 : 0)
        let titleMaxW = max(40, w - titleX - rightReserved)
        titleLabel.frame = NSRect(
            x: titleX,
            y: floor((h - 18) * 0.5),
            width: titleMaxW,
            height: 18
        )
    }
}

// MARK: - Ephemeral Panel Controller

public final class HistoryPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
    private let store: HistoryStore
    private let monitor: ClipboardMonitor

    private var panel: HistoryPanel?
    private weak var statusBarButton: NSStatusBarButton?
    private weak var searchField: NSTextField?
    private weak var countBadgeLabel: NSTextField?
    private weak var tableView: HoverTableView?
    private weak var scrollView: NSScrollView?
    private weak var emptyStateLabel: NSTextField?
    private weak var metadataLabel: NSTextField?
    private weak var clearButton: HoverFooterButton?
    private weak var settingsButton: HoverFooterButton?
    private weak var quitButton: HoverFooterButton?
    private weak var topSeparator: NSBox?
    private weak var bottomSeparator: NSBox?
    private weak var footerBarView: NSView?

    private var filteredItems: [ClipboardItem] = []
    private var previousApp: NSRunningApplication?
    private var resignObserver: NSObjectProtocol?
    private var globalMouseMonitor: Any?
    private var closeGeneration: UInt64 = 0
    private var lastAutoCloseTime: CFAbsoluteTime = 0
    private var isShowingSubmenu = false

    public var onVisibilityChanged: ((Bool) -> Void)?

    public static let defaultPanelWidth: CGFloat = 384
    private let panelWidth: CGFloat = HistoryPanelController.defaultPanelWidth
    private let headerHeight: CGFloat = 40
    private let footerHeight: CGFloat = 58
    private let rowHeight: CGFloat = 30

    public var isVisible: Bool {
        panel?.isVisible == true
    }

    public init(store: HistoryStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        super.init()
    }

    /// Race-free toggle specifically designed for NSStatusBarButton clicks
    public func toggleFromStatusBar(anchorButton: NSStatusBarButton?) {
        self.statusBarButton = anchorButton
        if isVisible {
            // Defer restoring focus by one runloop turn so NSStatusBarButton finishes click tracking cleanly
            close(restoreFocus: true, deferFocusRestore: true)
        } else {
            // Guard against macOS focus-loss closing the panel milliseconds before statusBarClicked fires
            if CFAbsoluteTimeGetCurrent() - lastAutoCloseTime < 0.30 {
                return
            }
            open(anchorButton: anchorButton)
        }
    }

    public func toggleFromHotKey(anchorButton: NSStatusBarButton?) {
        self.statusBarButton = anchorButton
        if isVisible {
            close(restoreFocus: true, deferFocusRestore: false)
        } else {
            open(anchorButton: anchorButton)
        }
    }

    public func open(anchorButton: NSStatusBarButton?) {
        closeGeneration &+= 1
        self.statusBarButton = anchorButton

        let frontApp = NSWorkspace.shared.frontmostApplication
        if frontApp?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontApp
        }

        let panelInstance = ensurePanelCreated()
        filteredItems = store.items

        searchField?.stringValue = ""
        reloadUIAndResize(anchorButton: anchorButton, reposition: true)

        NSApp.activate(ignoringOtherApps: true)
        panelInstance.makeKeyAndOrderFront(nil)
        panelInstance.acceptsMouseMovedEvents = true
        if let sf = searchField {
            panelInstance.makeFirstResponder(sf)
        }

        // Sync selection to mouse cursor only (no forced blue highlight on row 0)
        tableView?.syncHoverToCurrentMouse()
        clearButton?.refreshHoverFromMouseLocation()
        settingsButton?.refreshHoverFromMouseLocation()
        quitButton?.refreshHoverFromMouseLocation()
        updateMetadataLine()

        installDismissObservers()
        onVisibilityChanged?(true)
    }

    public func close(restoreFocus: Bool, deferFocusRestore: Bool = false, isAutoDismiss: Bool = false) {
        guard let activePanel = panel else { return }

        if isAutoDismiss {
            lastAutoCloseTime = CFAbsoluteTimeGetCurrent()
        }

        removeDismissObservers()
        activePanel.orderOut(nil)
        onVisibilityChanged?(false)

        if restoreFocus, let prev = previousApp, !prev.isTerminated {
            if deferFocusRestore {
                DispatchQueue.main.async {
                    if !prev.isTerminated {
                        prev.activate(options: [])
                    }
                }
            } else {
                prev.activate(options: [])
            }
        }

        let expectedGen = closeGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.closeGeneration == expectedGen, !(self.panel?.isVisible ?? false) else {
                return
            }
            self.filteredItems.removeAll(keepingCapacity: false)
            self.panel = nil
        }
    }

    public func refreshIfVisible() {
        guard isVisible else { return }
        let query = searchField?.stringValue ?? ""
        filteredItems = store.search(query: query)
        reloadUIAndResize(anchorButton: nil, reposition: false)
    }

    // MARK: - Build Panel On Demand

    private func ensurePanelCreated() -> HistoryPanel {
        if let existing = panel {
            return existing
        }

        let style: NSWindow.StyleMask = [.titled, .fullSizeContentView, .nonactivatingPanel]
        let newPanel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 320),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        newPanel.isReleasedWhenClosed = false
        newPanel.level = .popUpMenu
        newPanel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true
        newPanel.isMovable = false
        newPanel.hasShadow = true
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.acceptsMouseMovedEvents = true
        newPanel.animationBehavior = .utilityWindow

        newPanel.standardWindowButton(.closeButton)?.isHidden = true
        newPanel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newPanel.standardWindowButton(.zoomButton)?.isHidden = true

        let rootView: NSView
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let solid = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 320))
            solid.wantsLayer = true
            solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            solid.layer?.cornerRadius = 11
            solid.layer?.masksToBounds = true
            rootView = solid
        } else {
            let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 320))
            effect.material = .menu
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 11
            effect.layer?.masksToBounds = true
            rootView = effect
        }
        rootView.autoresizingMask = [.width, .height]
        newPanel.contentView = rootView

        // Header
        let searchIcon = NSImageView(frame: NSRect(x: 16, y: 0, width: 15, height: 15))
        if let img = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Ara") {
            searchIcon.image = img.withSymbolConfiguration(.init(pointSize: 12.5, weight: .medium))
            searchIcon.contentTintColor = .secondaryLabelColor
        }
        searchIcon.tag = 101
        rootView.addSubview(searchIcon)

        let sf = NSTextField(frame: .zero)
        sf.placeholderString = "Geçmişte ara…"
        sf.isBordered = false
        sf.drawsBackground = false
        sf.focusRingType = .none
        sf.font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        sf.textColor = .labelColor
        sf.delegate = self
        sf.cell?.sendsActionOnEndEditing = false
        sf.cell?.usesSingleLineMode = true
        sf.cell?.isScrollable = true
        rootView.addSubview(sf)
        self.searchField = sf

        let badge = NSTextField(labelWithString: "")
        badge.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        badge.textColor = .tertiaryLabelColor
        badge.alignment = .right
        rootView.addSubview(badge)
        self.countBadgeLabel = badge

        let topSep = NSBox()
        topSep.boxType = .separator
        rootView.addSubview(topSep)
        self.topSeparator = topSep

        // Scrollable HoverTableView
        let sv = NSScrollView(frame: NSRect(x: 0, y: footerHeight, width: panelWidth, height: 180))
        sv.drawsBackground = false
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.scrollerStyle = .overlay
        sv.borderType = .noBorder
        sv.contentInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        sv.automaticallyAdjustsContentInsets = false

        let tv = HoverTableView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 180))
        tv.style = .plain
        tv.headerView = nil
        tv.backgroundColor = .clear
        tv.rowHeight = rowHeight
        tv.intercellSpacing = NSSize(width: 0, height: 2)
        tv.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tv.selectionHighlightStyle = .regular
        tv.allowsEmptySelection = true
        tv.allowsMultipleSelection = false
        tv.focusRingType = .none

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MainColumn"))
        col.minWidth = panelWidth
        col.maxWidth = panelWidth
        col.width = panelWidth
        col.resizingMask = .autoresizingMask
        tv.addTableColumn(col)

        tv.dataSource = self
        tv.delegate = self
        tv.target = self
        tv.action = #selector(handleTableRowClick)

        let rowContextMenu = NSMenu(title: "Öğe İşlemleri")
        rowContextMenu.delegate = self
        tv.menu = rowContextMenu

        sv.documentView = tv
        rootView.addSubview(sv)
        self.scrollView = sv
        self.tableView = tv

        // Empty state label
        let empty = NSTextField(labelWithString: "Henüz kopyalanan öğe yok\nMetin, bağlantı, dosya veya görsel kopyalayın")
        empty.alignment = .center
        empty.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        empty.textColor = .secondaryLabelColor
        empty.maximumNumberOfLines = 2
        empty.isHidden = true
        rootView.addSubview(empty)
        self.emptyStateLabel = empty

        // Footer separator + Metadata + Hover Action Buttons
        let botSep = NSBox()
        botSep.boxType = .separator
        rootView.addSubview(botSep)
        self.bottomSeparator = botSep

        let footer = NSView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: footerHeight))
        rootView.addSubview(footer)
        self.footerBarView = footer

        let meta = NSTextField(labelWithString: "")
        meta.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        meta.textColor = .secondaryLabelColor
        meta.lineBreakMode = .byTruncatingTail
        meta.frame = NSRect(x: 16, y: 36, width: panelWidth - 32, height: 15)
        footer.addSubview(meta)
        self.metadataLabel = meta

        let clearBtn = HoverFooterButton(title: "Temizle", symbolName: "trash", target: self, action: #selector(clearButtonClicked))
        clearBtn.frame = NSRect(x: 10, y: 6, width: 88, height: 26)
        footer.addSubview(clearBtn)
        self.clearButton = clearBtn

        let settingsBtn = HoverFooterButton(title: "Ayarlar", symbolName: "gearshape", target: self, action: #selector(settingsButtonClicked))
        settingsBtn.frame = NSRect(x: 102, y: 6, width: 92, height: 26)
        footer.addSubview(settingsBtn)
        self.settingsButton = settingsBtn

        let quitBtn = HoverFooterButton(title: "Çıkış", symbolName: "xmark.circle", target: self, action: #selector(quitButtonClicked))
        quitBtn.frame = NSRect(x: panelWidth - 84, y: 6, width: 74, height: 26)
        footer.addSubview(quitBtn)
        self.quitButton = quitBtn

        // Keyboard hooks
        newPanel.onEscape = { [weak self] in
            self?.close(restoreFocus: true)
        }
        newPanel.onMoveSelection = { [weak self] delta in
            self?.moveSelection(by: delta)
        }
        newPanel.onConfirmSelection = { [weak self] optPressed in
            self?.activateSelectedItem(plainTextOnly: optPressed)
        }
        newPanel.onCopyOnlySelected = { [weak self] in
            self?.copySelectedItemWithoutOpening()
        }
        newPanel.onRevealSelectedInFinder = { [weak self] in
            self?.revealSelectedItemInFinder()
        }
        newPanel.onQuickSelect = { [weak self] idx in
            self?.quickSelect(index: idx)
        }
        newPanel.onTogglePin = { [weak self] in
            self?.togglePinSelectedItem()
        }
        newPanel.onDeleteSelected = { [weak self] in
            self?.deleteSelectedItem()
        }
        newPanel.onClearUnpinned = { [weak self] in
            self?.store.clear(includingPinned: false)
        }
        newPanel.onOpenSettings = { [weak self] in
            self?.settingsButtonClicked()
        }

        self.panel = newPanel
        return newPanel
    }

    // MARK: - Layout & Dynamic Sizing

    private func reloadUIAndResize(anchorButton: NSStatusBarButton?, reposition: Bool) {
        guard let activePanel = panel, let contentView = activePanel.contentView else { return }

        let settings = AppSettings.shared
        if settings.isPaused {
            countBadgeLabel?.stringValue = "Duraklatıldı"
            countBadgeLabel?.textColor = .systemOrange
        } else {
            countBadgeLabel?.stringValue = "\(filteredItems.count) öğe"
            countBadgeLabel?.textColor = .tertiaryLabelColor
        }

        let rowPitch = rowHeight + 2
        let visibleRows = min(max(filteredItems.count, 3), 11)
        let listHeight = CGFloat(visibleRows) * rowPitch + 8
        let totalHeight = headerHeight + listHeight + footerHeight

        var targetFrame = activePanel.frame
        if reposition {
            let origin = computeAnchorOrigin(panelSize: NSSize(width: panelWidth, height: totalHeight), anchorButton: anchorButton)
            targetFrame = NSRect(origin: origin, size: NSSize(width: panelWidth, height: totalHeight))
        } else {
            let topY = targetFrame.maxY
            targetFrame.size = NSSize(width: panelWidth, height: totalHeight)
            targetFrame.origin.y = topY - totalHeight
        }

        activePanel.setFrame(targetFrame, display: true)

        let headerY = totalHeight - headerHeight
        if let searchIcon = contentView.viewWithTag(101) {
            searchIcon.frame = NSRect(x: 16, y: headerY + 12, width: 15, height: 15)
        }
        countBadgeLabel?.frame = NSRect(x: panelWidth - 98, y: headerY + 12, width: 82, height: 16)
        searchField?.frame = NSRect(x: 38, y: headerY + 10, width: panelWidth - 144, height: 20)
        topSeparator?.frame = NSRect(x: 0, y: headerY, width: panelWidth, height: 1)

        scrollView?.frame = NSRect(x: 0, y: footerHeight, width: panelWidth, height: listHeight)
        scrollView?.layoutSubtreeIfNeeded()
        if let tv = tableView, let col = tv.tableColumns.first {
            let exactWidth = scrollView?.contentSize.width ?? panelWidth
            col.minWidth = exactWidth
            col.maxWidth = exactWidth
            col.width = exactWidth
            tv.frame.size.width = exactWidth
            tv.sizeLastColumnToFit()
        }

        emptyStateLabel?.frame = NSRect(x: 20, y: footerHeight + floor((listHeight - 36) * 0.5), width: panelWidth - 40, height: 36)
        emptyStateLabel?.isHidden = !filteredItems.isEmpty
        if filteredItems.isEmpty {
            let query = (searchField?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            emptyStateLabel?.stringValue = query.isEmpty
                ? "Henüz kopyalanan öğe yok\nMetin, bağlantı, dosya veya görsel kopyalayın"
                : "“\(query)” ile eşleşen sonuç bulunamadı"
        }

        bottomSeparator?.frame = NSRect(x: 0, y: footerHeight - 1, width: panelWidth, height: 1)
        footerBarView?.frame = NSRect(x: 0, y: 0, width: panelWidth, height: footerHeight - 1)

        tableView?.reloadData()
        tableView?.deselectAll(nil)
        tableView?.syncHoverToCurrentMouse()
        updateMetadataLine()
    }

    private func computeAnchorOrigin(panelSize: NSSize, anchorButton: NSStatusBarButton?) -> NSPoint {
        if let button = anchorButton,
           let buttonWindow = button.window,
           buttonWindow.frame.width > 0 {
            let btnFrame = buttonWindow.frame
            let targetScreen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first
            let visible = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

            var x = round(btnFrame.midX - panelSize.width * 0.5)
            x = max(visible.minX + 8, min(x, visible.maxX - panelSize.width - 8))
            let y = max(visible.minY + 8, btnFrame.minY - panelSize.height - 4)
            return NSPoint(x: x, y: y)
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let x = max(visible.minX + 12, min(round(mouse.x - panelSize.width * 0.5), visible.maxX - panelSize.width - 12))
        let y = max(visible.minY + 12, min(round(mouse.y - panelSize.height * 0.35), visible.maxY - panelSize.height - 12))
        return NSPoint(x: x, y: y)
    }

    // MARK: - Search, Hover & Keyboard Selection Logic

    public func controlTextDidChange(_ obj: Notification) {
        let query = searchField?.stringValue ?? ""
        filteredItems = store.search(query: query)
        reloadUIAndResize(anchorButton: nil, reposition: false)
    }

    private func moveSelection(by delta: Int) {
        guard !filteredItems.isEmpty, let tv = tableView else { return }
        let next: Int
        if tv.selectedRow < 0 {
            next = delta >= 0 ? 0 : filteredItems.count - 1
        } else {
            next = max(0, min(filteredItems.count - 1, tv.selectedRow + delta))
        }
        tv.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tv.scrollRowToVisible(next)
        updateMetadataLine()
    }

    private func effectiveTargetRow() -> Int? {
        guard !filteredItems.isEmpty, let tv = tableView else { return nil }
        if tv.selectedRow >= 0 && tv.selectedRow < filteredItems.count {
            return tv.selectedRow
        }
        // Fallback to top item if user immediately presses Return after typing a search
        return 0
    }

    private func quickSelect(index: Int) {
        guard index >= 0 && index < filteredItems.count else { return }
        performPrimaryAction(on: filteredItems[index], forceCopyOnly: false, plainTextOnly: false)
    }

    private func activateSelectedItem(plainTextOnly: Bool) {
        guard let idx = effectiveTargetRow() else { return }
        performPrimaryAction(on: filteredItems[idx], forceCopyOnly: false, plainTextOnly: plainTextOnly)
    }

    private func copySelectedItemWithoutOpening() {
        guard let idx = effectiveTargetRow() else { return }
        performPrimaryAction(on: filteredItems[idx], forceCopyOnly: true, plainTextOnly: false)
    }

    private func revealSelectedItemInFinder() {
        guard let tv = tableView, tv.selectedRow >= 0, tv.selectedRow < filteredItems.count else { return }
        let item = filteredItems[tv.selectedRow]
        guard item.kind == .file, let paths = item.filePaths, !paths.isEmpty else { return }

        let existingURLs = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        guard !existingURLs.isEmpty else {
            NSSound.beep()
            return
        }
        close(restoreFocus: false)
        NSWorkspace.shared.activateFileViewerSelecting(existingURLs)
    }

    private func performPrimaryAction(on item: ClipboardItem, forceCopyOnly: Bool, plainTextOnly: Bool) {
        if item.kind == .file && AppSettings.shared.openFilesOnSelect && !forceCopyOnly && !plainTextOnly {
            openFileItem(item)
            return
        }

        let targetApp = previousApp
        monitor.copyItemToPasteboard(item, plainTextOnly: plainTextOnly)
        close(restoreFocus: true)

        if AppSettings.shared.autoPasteOnSelect, let app = targetApp, !app.isTerminated {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                _ = app
                ClipboardMonitor.synthesizeCommandV()
            }
        }
    }

    private func openFileItem(_ item: ClipboardItem) {
        guard let paths = item.filePaths, !paths.isEmpty else { return }
        let existingURLs = paths
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }

        guard !existingURLs.isEmpty else {
            NSSound.beep()
            return
        }

        store.bumpToTop(id: item.id)
        close(restoreFocus: false)

        for url in existingURLs {
            NSWorkspace.shared.open(url)
        }
    }

    private func togglePinSelectedItem() {
        guard let tv = tableView, tv.selectedRow >= 0, tv.selectedRow < filteredItems.count else { return }
        let targetID = filteredItems[tv.selectedRow].id
        store.togglePin(id: targetID)

        let query = searchField?.stringValue ?? ""
        filteredItems = store.search(query: query)
        reloadUIAndResize(anchorButton: nil, reposition: false)
        if let newIdx = filteredItems.firstIndex(where: { $0.id == targetID }) {
            tv.selectRowIndexes(IndexSet(integer: newIdx), byExtendingSelection: false)
            tv.scrollRowToVisible(newIdx)
            updateMetadataLine()
        }
    }

    private func deleteSelectedItem() {
        guard let tv = tableView, tv.selectedRow >= 0, tv.selectedRow < filteredItems.count else { return }
        let idx = tv.selectedRow
        let id = filteredItems[idx].id
        store.delete(id: id)

        let query = searchField?.stringValue ?? ""
        filteredItems = store.search(query: query)
        reloadUIAndResize(anchorButton: nil, reposition: false)
    }

    private func updateMetadataLine() {
        guard let tv = tableView else { return }
        let idx = tv.selectedRow
        guard idx >= 0 && idx < filteredItems.count else {
            metadataLabel?.stringValue = filteredItems.isEmpty
                ? "Kopyalanan öğeler otomatik kaydedilir"
                : "Seçmek için imleci öğenin üzerine getirin veya ↑↓ kullanın"
            return
        }
        let item = filteredItems[idx]
        var parts: [String] = []
        if let app = item.sourceAppName, !app.isEmpty {
            parts.append(app)
        }
        parts.append(Self.relativeTimeText(since: item.createdAt))
        switch item.kind {
        case .text, .url:
            let charCount = item.textContent?.count ?? item.byteSize
            parts.append("\(charCount) krk")
            parts.append("Tıkla Kopyala • ⌥P Sabitle • ⌥⌫ Sil")
        case .file:
            let cnt = item.filePaths?.count ?? 1
            parts.append("\(cnt) dosya")
            if AppSettings.shared.openFilesOnSelect {
                parts.append("Tıkla Aç • ⌘R Finder • ⌥P Sabitle • ⌥⌫ Sil")
            } else {
                parts.append("Tıkla Kopyala • ⌘R Finder • ⌥P Sabitle • ⌥⌫ Sil")
            }
        case .image:
            let sizeStr = ByteCountFormatter.string(fromByteCount: Int64(item.byteSize), countStyle: .file)
            parts.append(sizeStr)
            parts.append("Tıkla Kopyala • ⌥P Sabitle • ⌥⌫ Sil")
        }
        metadataLabel?.stringValue = parts.joined(separator: "  ·  ")
    }

    private static func relativeTimeText(since date: Date) -> String {
        let sec = max(0, Int(Date().timeIntervalSince(date)))
        if sec < 45 { return "Az önce" }
        let min = sec / 60
        if min < 60 { return "\(min) dk önce" }
        let hr = min / 60
        if hr < 24 { return "\(hr) sa önce" }
        let days = hr / 24
        if days == 1 { return "Dün" }
        return "\(days) gün önce"
    }

    // MARK: - TableView Delegate / DataSource / Clicks

    public func numberOfRows(in tableView: NSTableView) -> Int {
        filteredItems.count
    }

    public func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        RoundedSelectionRowView()
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0 && row < filteredItems.count else { return nil }
        let cell: HistoryCellView
        if let reused = tableView.makeView(withIdentifier: HistoryCellView.identifier, owner: nil) as? HistoryCellView {
            cell = reused
        } else {
            cell = HistoryCellView(frame: .zero)
            cell.identifier = HistoryCellView.identifier
        }
        cell.configure(item: filteredItems[row], index: row)
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        updateMetadataLine()
    }

    @objc private func handleTableRowClick() {
        guard let tv = tableView else { return }
        let clicked = tv.clickedRow
        guard clicked >= 0 && clicked < filteredItems.count else { return }
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plainOnly = flags.contains(.option)
        let cmdCopy = flags.contains(.command)
        performPrimaryAction(on: filteredItems[clicked], forceCopyOnly: cmdCopy, plainTextOnly: plainOnly)
    }

    // MARK: - Row Right-Click Context Menu

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let tv = tableView else { return }
        let row = tv.clickedRow >= 0 ? tv.clickedRow : tv.selectedRow
        guard row >= 0 && row < filteredItems.count else { return }

        tv.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        let item = filteredItems[row]

        if item.kind == .file {
            let openItem = NSMenuItem(title: "Dosyayı Aç", action: #selector(contextOpenFile), keyEquivalent: "\r")
            openItem.keyEquivalentModifierMask = []
            openItem.target = self
            menu.addItem(openItem)

            let revealItem = NSMenuItem(title: "Finder'da Göster", action: #selector(contextRevealInFinder), keyEquivalent: "r")
            revealItem.keyEquivalentModifierMask = [.command]
            revealItem.target = self
            menu.addItem(revealItem)

            let copyFileItem = NSMenuItem(title: "Dosyayı Panoya Kopyala", action: #selector(contextCopyOnly), keyEquivalent: "c")
            copyFileItem.keyEquivalentModifierMask = [.command]
            copyFileItem.target = self
            menu.addItem(copyFileItem)

            let copyPathItem = NSMenuItem(title: "Dosya Yolunu Kopyala", action: #selector(contextCopyPlain), keyEquivalent: "\r")
            copyPathItem.keyEquivalentModifierMask = [.option]
            copyPathItem.target = self
            menu.addItem(copyPathItem)
        } else {
            let copyItem = NSMenuItem(title: "Kopyala", action: #selector(contextCopyOnly), keyEquivalent: "\r")
            copyItem.keyEquivalentModifierMask = []
            copyItem.target = self
            menu.addItem(copyItem)

            let plainItem = NSMenuItem(title: "Düz Metin Olarak Kopyala", action: #selector(contextCopyPlain), keyEquivalent: "\r")
            plainItem.keyEquivalentModifierMask = [.option]
            plainItem.target = self
            menu.addItem(plainItem)

            if item.kind == .url {
                let openURLItem = NSMenuItem(title: "Tarayıcıda Aç", action: #selector(contextOpenURL), keyEquivalent: "o")
                openURLItem.keyEquivalentModifierMask = [.command]
                openURLItem.target = self
                menu.addItem(openURLItem)
            }
        }

        menu.addItem(.separator())

        let pinTitle = item.isPinned ? "Sabitlemeyi Kaldır" : "Üste Sabitle"
        let pinItem = NSMenuItem(title: pinTitle, action: #selector(contextTogglePin), keyEquivalent: "p")
        pinItem.keyEquivalentModifierMask = [.option]
        pinItem.target = self
        menu.addItem(pinItem)

        let delItem = NSMenuItem(title: "Sil", action: #selector(contextDelete), keyEquivalent: "\u{8}")
        delItem.keyEquivalentModifierMask = [.option]
        delItem.target = self
        menu.addItem(delItem)
    }

    @objc private func contextOpenFile() {
        guard let tv = tableView, tv.selectedRow >= 0, tv.selectedRow < filteredItems.count else { return }
        openFileItem(filteredItems[tv.selectedRow])
    }

    @objc private func contextRevealInFinder() {
        revealSelectedItemInFinder()
    }

    @objc private func contextOpenURL() {
        guard let tv = tableView, tv.selectedRow >= 0, tv.selectedRow < filteredItems.count else { return }
        let item = filteredItems[tv.selectedRow]
        guard let str = item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: str) else { return }
        close(restoreFocus: false)
        NSWorkspace.shared.open(url)
    }

    @objc private func contextCopyOnly() {
        copySelectedItemWithoutOpening()
    }

    @objc private func contextCopyPlain() {
        activateSelectedItem(plainTextOnly: true)
    }

    @objc private func contextTogglePin() {
        togglePinSelectedItem()
    }

    @objc private func contextDelete() {
        deleteSelectedItem()
    }

    // MARK: - Footer Button Actions

    @objc private func clearButtonClicked() {
        let includePinned = NSEvent.modifierFlags.contains(.option)
        store.clear(includingPinned: includePinned)
        refreshIfVisible()
    }

    @objc private func settingsButtonClicked() {
        guard let btn = settingsButton else { return }
        isShowingSubmenu = true
        let menu = SettingsMenuHandler.shared.buildMenu(includeQuickHeader: false)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: btn.bounds.height + 4), in: btn)
        isShowingSubmenu = false
        btn.refreshHoverFromMouseLocation()
        clearButton?.refreshHoverFromMouseLocation()
        quitButton?.refreshHoverFromMouseLocation()
    }

    @objc private func quitButtonClicked() {
        NSApp.terminate(nil)
    }

    // MARK: - Race-Free Dismiss Observers (Ignores Status Bar Icon Clicks!)

    private func isMouseOverStatusBarButton() -> Bool {
        guard let btnWindow = statusBarButton?.window else { return false }
        let padded = btnWindow.frame.insetBy(dx: -8, dy: -8)
        return padded.contains(NSEvent.mouseLocation)
    }

    private func installDismissObservers() {
        removeDismissObservers()

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, !self.isShowingSubmenu else { return }
            if self.isMouseOverStatusBarButton() {
                // Let statusBarClicked toggle the panel cleanly without close+reopen race!
                return
            }
            self.close(restoreFocus: false, isAutoDismiss: true)
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard let self = self, !self.isShowingSubmenu else { return }
            if self.isMouseOverStatusBarButton() {
                return
            }
            if let panelFrame = self.panel?.frame, panelFrame.contains(NSEvent.mouseLocation) {
                return
            }
            self.close(restoreFocus: false, isAutoDismiss: true)
        }
    }

    private func removeDismissObservers() {
        if let obs = resignObserver {
            NotificationCenter.default.removeObserver(obs)
            resignObserver = nil
        }
        if let mon = globalMouseMonitor {
            NSEvent.removeMonitor(mon)
            globalMouseMonitor = nil
        }
    }
}
