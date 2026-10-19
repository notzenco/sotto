import Foundation

/// One dictation's kept audio, described as plain JSON next to the clip.
public struct ClipRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var bundleID: String?
    public var domain: String?
    public var durationSeconds: Double
    public var typingModel: SpeechModelID
    public var rawText: String
    public var hintedText: String
    public var typedText: String
    public var teacherModel: SpeechModelID?
    public var teacherText: String?
    /// Keyed by `SpeechModelID.rawValue` so the JSON stays a plain object.
    public var modelTexts: [String: String]
    public var pickedModel: SpeechModelID?
    public var correctedText: String?

    public init(id: UUID = UUID(), date: Date, bundleID: String? = nil, domain: String? = nil,
                durationSeconds: Double, typingModel: SpeechModelID,
                rawText: String, hintedText: String, typedText: String,
                teacherModel: SpeechModelID? = nil, teacherText: String? = nil,
                modelTexts: [String: String] = [:], pickedModel: SpeechModelID? = nil,
                correctedText: String? = nil) {
        self.id = id
        self.date = date
        self.bundleID = bundleID
        self.domain = domain
        self.durationSeconds = durationSeconds
        self.typingModel = typingModel
        self.rawText = rawText
        self.hintedText = hintedText
        self.typedText = typedText
        self.teacherModel = teacherModel
        self.teacherText = teacherText
        self.modelTexts = modelTexts
        self.pickedModel = pickedModel
        self.correctedText = correctedText
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            date: try container.decode(Date.self, forKey: .date),
            bundleID: try container.decodeIfPresent(String.self, forKey: .bundleID),
            domain: try container.decodeIfPresent(String.self, forKey: .domain),
            durationSeconds: try container.decode(Double.self, forKey: .durationSeconds),
            typingModel: try container.decode(SpeechModelID.self, forKey: .typingModel),
            rawText: try container.decode(String.self, forKey: .rawText),
            hintedText: try container.decode(String.self, forKey: .hintedText),
            typedText: try container.decode(String.self, forKey: .typedText),
            teacherModel: try container.decodeIfPresent(SpeechModelID.self, forKey: .teacherModel),
            teacherText: try container.decodeIfPresent(String.self, forKey: .teacherText),
            modelTexts: try container.decodeIfPresent([String: String].self, forKey: .modelTexts) ?? [:],
            pickedModel: try container.decodeIfPresent(SpeechModelID.self, forKey: .pickedModel),
            correctedText: try container.decodeIfPresent(String.self, forKey: .correctedText)
        )
    }
}

public enum ClipRetention {
    public static let days = 7

    public static func expired(_ records: [ClipRecord], now: Date) -> [ClipRecord] {
        let limit = TimeInterval(days * 86_400)
        return records.filter { now.timeIntervalSince($0.date) >= limit }
    }
}

public struct ModelScore: Equatable, Sendable {
    public var right: Int
    public var judged: Int

    public init(right: Int, judged: Int) {
        self.right = right
        self.judged = judged
    }
}

public enum CompareScore {
    /// A clip is judged once it has a Compare pick or a corrected text. A model is right when it was picked,
    /// or its text matches the picked model's text or the corrected text, ignoring case, punctuation and
    /// spelling variety (Sotto respells before typing, so "color" and "colour" are both right).
    public static func tally(_ records: [ClipRecord]) -> [SpeechModelID: ModelScore] {
        var scores: [SpeechModelID: ModelScore] = [:]
        for record in records where record.pickedModel != nil || record.correctedText != nil {
            let corrected = record.correctedText.map(normalized)
            let picked = record.pickedModel.flatMap { record.modelTexts[$0.rawValue] }.map(normalized)
            for (key, text) in record.modelTexts {
                guard let model = SpeechModelID(rawValue: key) else { continue }
                let plain = normalized(text)
                let right = model == record.pickedModel || plain == picked || plain == corrected
                var score = scores[model] ?? ModelScore(right: 0, judged: 0)
                score.judged += 1
                if right { score.right += 1 }
                scores[model] = score
            }
        }
        return scores
    }

    private static func normalized(_ text: String) -> String {
        PhraseAligner.ignoringSpelling(
            String(text.lowercased().unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) })
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
