//
//  EventMonitors.swift
//  ClaudeIsland
//
//  Publishes the global mouse location without needing Accessibility
//  permission. The previous implementation used `NSEvent.addGlobalMonitorFor
//  Events` which triggered macOS's AX prompt — instead we poll `NSEvent.
//  mouseLocation` at 60Hz, which is a permission-free API that simply reads
//  the current cursor position.
//
//  Polling cost is negligible (one CGS call per frame) and the notch UX only
//  needs millisecond-level accuracy to feel instant.
//

import AppKit
import Combine

class EventMonitors {
    static let shared = EventMonitors()

    let mouseLocation = CurrentValueSubject<CGPoint, Never>(.zero)
    /// Fires when a click is delivered to one of our own windows. Used to
    /// dismiss the panel when the click lands outside the hit-test area —
    /// addLocalMonitorForEvents is in-process only and doesn't need AX.
    let localMouseDown = PassthroughSubject<NSEvent, Never>()

    private var pollTimer: Timer?
    private var localMouseMonitor: Any?
    private let pollInterval: TimeInterval = 1.0 / 60.0

    private init() {
        start()
    }

    private func start() {
        // Prime the subject with the initial cursor position so subscribers
        // don't start from .zero when the cursor happens to already be over
        // the notch at launch.
        mouseLocation.send(NSEvent.mouseLocation)

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = NSEvent.mouseLocation
            // Skip identical samples — Combine's throttle would filter them
            // anyway but avoiding the publish saves a downstream hop.
            if current != self.mouseLocation.value {
                self.mouseLocation.send(current)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            self?.localMouseDown.send(event)
            return event
        }
    }

    deinit {
        pollTimer?.invalidate()
        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
