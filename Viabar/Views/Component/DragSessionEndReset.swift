import AppKit
import SwiftUI

extension View {
    func dragSessionEndReset(isActive: Bool, onEnd: @escaping () -> Void) -> some View {
        background {
            DragSessionEndMonitor(isActive: isActive, onEnd: onEnd)
                .frame(width: 0, height: 0)
        }
    }
}

private struct DragSessionEndMonitor: NSViewRepresentable {
    let isActive: Bool
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isActive: isActive, onEnd: onEnd)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    final class Coordinator {
        private var localMonitor: Any?
        private var globalMonitor: Any?
        private var mouseButtonTimer: Timer?
        private var isActive = false
        private var isResetScheduled = false
        private var onEnd: (() -> Void)?

        func update(isActive: Bool, onEnd: @escaping () -> Void) {
            self.isActive = isActive
            self.onEnd = onEnd

            if isActive {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }

        func stopMonitoring() {
            if let localMonitor {
                NSEvent.removeMonitor(localMonitor)
                self.localMonitor = nil
            }
            if let globalMonitor {
                NSEvent.removeMonitor(globalMonitor)
                self.globalMonitor = nil
            }
            mouseButtonTimer?.invalidate()
            mouseButtonTimer = nil
            isActive = false
        }

        private func startMonitoring() {
            guard localMonitor == nil,
                  globalMonitor == nil,
                  mouseButtonTimer == nil
            else { return }

            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                self?.scheduleReset()
                return event
            }
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
                self?.scheduleReset()
            }

            // Native drag tracking can consume mouse-up events before event monitors see them.
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self?.scheduleReset()
            }
            mouseButtonTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }

        private func scheduleReset() {
            guard isActive, !isResetScheduled else { return }
            isResetScheduled = true

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isResetScheduled = false
                guard isActive else { return }
                onEnd?()
            }
        }

        deinit {
            stopMonitoring()
        }
    }
}
