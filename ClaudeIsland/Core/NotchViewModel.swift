//
//  NotchViewModel.swift
//  ClaudeIsland
//
//  State management for the dynamic island
//

import AppKit
import Combine
import SwiftUI

enum NotchStatus: Equatable {
    case closed
    case opened
    case popping
}

enum NotchOpenReason {
    case click
    case hover
    case notification
    case boot
    case unknown
}

enum NotchContentType: Equatable {
    case instances
    case menu

    var id: String {
        switch self {
        case .instances: return "instances"
        case .menu: return "menu"
        }
    }
}

@MainActor
class NotchViewModel: ObservableObject {
    // MARK: - Published State

    @Published var status: NotchStatus = .closed
    @Published var openReason: NotchOpenReason = .unknown
    @Published var contentType: NotchContentType = .instances
    @Published var isHovering: Bool = false

    // MARK: - Dependencies

    private let screenSelector = ScreenSelector.shared
    private let soundSelector = SoundSelector.shared
    private let approvalSoundSelector = SoundSelector.approval
    private let claudeDirSelector = ClaudeDirSelector.shared

    // MARK: - Geometry

    let geometry: NotchGeometry
    let spacing: CGFloat = 12
    let hasPhysicalNotch: Bool

    var deviceNotchRect: CGRect { geometry.deviceNotchRect }
    var screenRect: CGRect { geometry.screenRect }
    var windowHeight: CGFloat { geometry.windowHeight }

    /// Dynamic opened size based on content type
    var openedSize: CGSize {
        switch contentType {
        case .menu:
            // Base height covers all static rows (Back, 6 picker rows, 2
            // toggles, Accessibility, Update, Quit + 3 dividers + padding).
            // Picker expansion deltas added on top when expanded.
            return CGSize(
                width: min(screenRect.width * 0.4, 480),
                height: 620
                    + screenSelector.expandedPickerHeight
                    + soundSelector.expandedPickerHeight
                    + approvalSoundSelector.expandedPickerHeight
                    + claudeDirSelector.expandedPickerHeight
            )
        case .instances:
            return CGSize(
                width: min(screenRect.width * 0.4, 480),
                height: 320
            )
        }
    }

    // MARK: - Animation

    var animation: Animation {
        .easeOut(duration: 0.25)
    }

    // MARK: - Private

    private var cancellables = Set<AnyCancellable>()
    private var workspaceObserver: NSObjectProtocol?
    private let events = EventMonitors.shared

    /// Pending hover-open/hover-close work. Small grace periods filter out
    /// mouse-passing-through (open) and brief exits while scrolling or
    /// reaching for a button (close). Cancelled whenever hover state flips.
    private var openTimer: DispatchWorkItem?
    private var closeTimer: DispatchWorkItem?
    private let openDelay: TimeInterval = 0
    private let closeDelay: TimeInterval = 0

    /// Scheduled auto-close for notification-opened panels. Cancelled as
    /// soon as the user hovers in (engaging), status changes, or the
    /// panel is already closed by some other path.
    private var autoCloseTask: Task<Void, Never>?

    // MARK: - Initialization

    init(deviceNotchRect: CGRect, screenRect: CGRect, windowHeight: CGFloat, hasPhysicalNotch: Bool) {
        self.geometry = NotchGeometry(
            deviceNotchRect: deviceNotchRect,
            screenRect: screenRect,
            windowHeight: windowHeight
        )
        self.hasPhysicalNotch = hasPhysicalNotch
        setupEventHandlers()
        observeSelectors()
        observeAppSwitching()
    }

    deinit {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Close the panel whenever another application becomes frontmost.
    /// Handles the "click anywhere on screen" dismiss case reliably —
    /// our own panel is a nonactivating NSPanel so clicks inside it don't
    /// activate us, which means activation events only fire when the user
    /// clicks into a genuinely different app. Also covers clicks on the
    /// bottom 3/4 of the screen that fall outside our window's bounds and
    /// therefore never reach the local mouse monitor.
    private func observeAppSwitching() {
        let myBundleID = Bundle.main.bundleIdentifier
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != myBundleID else { return }
            guard let self, self.status == .opened else { return }
            self.notchClose()
        }
    }

    private func observeSelectors() {
        screenSelector.$isPickerExpanded
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        soundSelector.$isPickerExpanded
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        approvalSoundSelector.$isPickerExpanded
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        claudeDirSelector.$isPickerExpanded
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Event Handling

    private func setupEventHandlers() {
        events.mouseLocation
            .throttle(for: .milliseconds(50), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] location in
                self?.handleMouseMove(location)
            }
            .store(in: &cancellables)

        events.localMouseDown
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.handleLocalMouseDown()
            }
            .store(in: &cancellables)
    }

    /// Close the panel if a click lands inside our window but outside the
    /// hit-test panel area. `addLocalMonitorForEvents` only fires for events
    /// delivered to our own windows, which happens when `ignoresMouseEvents
    /// = false` (i.e. panel is open) — so the check is already effectively
    /// gated on `status == .opened`. The click is still consumed by the
    /// window's default sendEvent; we don't try to forward it to apps behind
    /// (that would need Accessibility). Users click a second time if they
    /// wanted to hit the app underneath.
    private func handleLocalMouseDown() {
        let location = NSEvent.mouseLocation
        guard status == .opened,
              geometry.isPointOutsidePanel(location, size: openedSize),
              !geometry.notchScreenRect.contains(location)
        else { return }
        notchClose()
    }

    private func handleMouseMove(_ location: CGPoint) {
        let inNotch = geometry.isPointInNotch(location)
        let inOpened = status == .opened && geometry.isPointInOpenedPanel(location, size: openedSize)

        let newHovering = inNotch || inOpened

        // Only update if changed to prevent unnecessary re-renders
        guard newHovering != isHovering else { return }

        isHovering = newHovering

        // Hover state just flipped — any pending grace-period work is stale.
        openTimer?.cancel(); openTimer = nil
        closeTimer?.cancel(); closeTimer = nil

        // Engaging with the panel (even briefly) cancels any pending
        // notification auto-close — the user noticed and wants to read.
        if newHovering { cancelAutoClose() }

        if newHovering {
            guard status == .closed || status == .popping else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isHovering else { return }
                self.notchOpen(reason: .hover)
            }
            openTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + openDelay, execute: work)
        } else {
            // Only hover-opened panels auto-close; click-opened panels stay
            // sticky so the user's explicit "pin this open" intent is kept.
            guard status == .opened && openReason == .hover else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.isHovering else { return }
                self.notchClose()
            }
            closeTimer = work
            DispatchQueue.main.asyncAfter(deadline: .now() + closeDelay, execute: work)
        }
    }

    // MARK: - Actions

    func notchOpen(reason: NotchOpenReason = .unknown) {
        openReason = reason
        status = .opened

        if reason == .notification {
            scheduleAutoCloseIfNeeded()
        }
    }

    func notchClose() {
        // Any pending auto-close is moot once the panel is closed.
        autoCloseTask?.cancel()
        autoCloseTask = nil

        status = .closed
        contentType = .instances
    }

    /// Arm a one-shot auto-close for notification-opened panels. Reads the
    /// delay from AppSettings (0 = disabled). Cancelled whenever the user
    /// hovers into the panel (see `cancelAutoClose`) or the panel closes
    /// for any reason.
    private func scheduleAutoCloseIfNeeded() {
        autoCloseTask?.cancel()
        autoCloseTask = nil

        let seconds = AppSettings.notificationAutoCloseSeconds
        guard seconds > 0 else { return }

        autoCloseTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled,
                  let self,
                  self.status == .opened,
                  self.openReason == .notification,
                  !self.isHovering  // safety: don't close while user is hovering
            else { return }
            self.notchClose()
        }
    }

    private func cancelAutoClose() {
        autoCloseTask?.cancel()
        autoCloseTask = nil
    }

    func notchPop() {
        guard status == .closed else { return }
        status = .popping
    }

    func notchUnpop() {
        guard status == .popping else { return }
        status = .closed
    }

    func toggleMenu() {
        contentType = contentType == .menu ? .instances : .menu
    }

    /// Perform boot animation: expand briefly then collapse
    func performBootAnimation() {
        notchOpen(reason: .boot)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.openReason == .boot else { return }
            self.notchClose()
        }
    }
}
