import AppKit
import SottoCore
import SwiftUI

@MainActor
final class IndicatorPanel {
    var onHide: (() -> Void)?
    var isVisible: Bool { panel.isVisible }

    private let panel: NSPanel
    private let state = IndicatorState()
    private let host: NSHostingView<IndicatorView>
    private var schedule = IndicatorSchedule()
    private var hideTask: Task<Void, Never>?
    private var screen: ScreenGeometry?
    private var caret: CGRect?

    init() {
        host = NSHostingView(rootView: IndicatorView(state: state))
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        // Setting isFloatingPanel resets the level to floating.
        panel.level = .statusBar
        panel.becomesKeyOnlyIfNeeded = true
        panel.backgroundColor = .clear
        host.sizingOptions = []
        panel.contentView = host
    }

    func apply(_ settings: IndicatorSettings) {
        state.settings = settings
        if !settings.showWords { state.words = "" }
        if isVisible { place() }
    }

    func show(_ phase: IndicatorPhase) {
        hideTask?.cancel()
        hideTask = nil
        let generation = schedule.show(phase)
        state.phase = phase

        if phase == .hidden {
            hide()
            return
        }
        if phase.linger == 0 {
            expire(generation)
            return
        }
        if case .listening = phase {
            state.effectiveStyle = nil
            state.words = ""
            state.level = 0
            selectScreen(caret: CaretLocator.caretRect())
        } else if screen == nil {
            // Permission failures can appear before a take has begun.
            selectScreen(caret: nil)
        }
        guard screen != nil else {
            hideNow()
            return
        }
        place()
        panel.orderFrontRegardless()

        if let seconds = phase.linger {
            hideTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(seconds)) }
                catch { return }
                self?.expire(generation)
            }
        }
    }

    func setLevel(_ level: Float) {
        state.level = level
    }

    func setWords(_ text: String) {
        guard state.settings.showWords else { return }
        state.words = text
        if isVisible { place() }
    }

    func hideNow() {
        hideTask?.cancel()
        hideTask = nil
        _ = schedule.show(.hidden)
        hide()
    }

    private func expire(_ generation: Int) {
        guard schedule.expire(generation) else { return }
        hideTask = nil
        hide()
    }

    private func hide() {
        state.phase = .hidden
        state.effectiveStyle = nil
        panel.orderOut(nil)
        screen = nil
        caret = nil
        onHide?()
    }

    private func selectScreen(caret rawCaret: CGRect?) {
        let screens = NSScreen.screens.map { screen in
            var notch: CGRect?
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                let rect = CGRect(x: left.maxX, y: max(left.minY, right.minY),
                                  width: right.minX - left.maxX,
                                  height: screen.frame.maxY - max(left.minY, right.minY))
                if rect.width > 0, rect.height > 0 { notch = rect }
            }
            return ScreenGeometry(frame: screen.frame, visibleFrame: screen.visibleFrame, notch: notch)
        }
        caret = IndicatorLayout.usableCaret(rawCaret, screens: screens)
        screen = IndicatorLayout.screenIndex(
            screens: screens, display: state.settings.display,
            position: state.settings.style == .notch ? .top : state.settings.position,
            pointer: NSEvent.mouseLocation, caret: caret
        ).map { screens[$0] }
        state.notch = screen?.notch
    }

    private func place() {
        guard let screen else { return }
        let placement = IndicatorLayout.place(
            body: IndicatorView.bodySize(for: state), caption: IndicatorView.captionSize(for: state),
            style: state.style, position: state.effectiveStyle == nil ? state.settings.position : .bottom,
            screen: screen, caret: caret
        )
        if placement.effectiveStyle != state.style {
            // Keep the fallback for the take and measure the actual pill, without saving a setting.
            state.effectiveStyle = placement.effectiveStyle
            place()
            return
        }
        let frame = placement.caption.map { placement.body.union($0) } ?? placement.body
        let local = IndicatorPlacement(
            body: placement.body.offsetBy(dx: -frame.minX, dy: -frame.minY),
            caption: placement.caption?.offsetBy(dx: -frame.minX, dy: -frame.minY),
            effectiveStyle: placement.effectiveStyle
        )
        panel.setFrame(frame, display: true)
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.rootView = IndicatorView(state: state, placement: local)
    }
}
