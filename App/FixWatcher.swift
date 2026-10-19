import ApplicationServices
import Foundation
import SottoCore

/// Reads a field back after Sotto types into it, to learn from the owner fixing a misheard word.
/// Checks about 20 seconds after inserting and when the next dictation starts, within 2 minutes.
@MainActor
final class FixWatcher {
    private static let delay: Duration = .seconds(20)
    /// How long the timed check waits while a take is listening or committing.
    private static let retry: Duration = .seconds(2)
    private static let window: TimeInterval = 120

    private let inserter: TextInserter
    private let isDictating: () -> Bool
    private let onFix: (Substitution) -> Void
    private var pending: (element: AXUIElement, text: String, offset: Int?, date: Date)?
    private var timer: Task<Void, Never>?

    init(inserter: TextInserter, isDictating: @escaping () -> Bool, onFix: @escaping (Substitution) -> Void) {
        self.inserter = inserter
        self.isDictating = isDictating
        self.onFix = onFix
    }

    /// Remembers the inserter's last insertion, replacing any pending one, and checks it shortly.
    /// The timed check waits out a take that is listening or committing, since the field read can take most of
    /// a second on the main actor; the take's own start check, or this one once it's over, reads the field.
    func watch() {
        timer?.cancel()
        pending = inserter.lastInsertion
        guard pending != nil else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            while !Task.isCancelled, self?.isDictating() == true {
                try? await Task.sleep(for: Self.retry)
            }
            guard !Task.isCancelled else { return }
            self?.check()
        }
    }

    /// Reads the field back. The insertion is dropped once a fix is found, the field is gone or hides its
    /// text, or 2 minutes have passed; a field with no fix yet stays watched for the next dictation.
    func check() {
        guard let insertion = pending else { return }
        guard Date().timeIntervalSince(insertion.date) <= Self.window,
              let text = inserter.fieldText(of: insertion.element) else {
            drop()
            return
        }
        guard let fix = FixDetector.fix(inserted: insertion.text, fieldText: text, near: insertion.offset) else {
            return
        }
        drop()
        onFix(fix)
    }

    private func drop() {
        pending = nil
        timer?.cancel()
        timer = nil
    }
}
