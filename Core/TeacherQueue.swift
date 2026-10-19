import Foundation

/// Which kept clips the teacher model still has to check, when it may run, and what it learns from a clip.
public enum TeacherQueue {
    /// The teacher waits for this long without a dictation.
    public static let idleSeconds: TimeInterval = 300

    public static func isIdle(lastDictation: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastDictation) >= idleSeconds
    }

    /// Clips with no teacher text that another model typed, oldest first. An empty teacher text marks a clip
    /// the teacher couldn't use, so it isn't tried again.
    public static func pending(_ records: [ClipRecord], teacher: SpeechModelID,
                               skipping skipped: Set<UUID> = []) -> [ClipRecord] {
        records
            .filter { $0.teacherText == nil && $0.typingModel != teacher && !skipped.contains($0.id) }
            .sorted { $0.date < $1.date }
    }

    /// The typing model's words the teacher heard differently, ignoring spelling variety.
    public static func substitutions(in record: ClipRecord, teacherText: String) -> [Substitution] {
        PhraseAligner.learningSubstitutions(from: record.rawText, to: teacherText)
    }
}
