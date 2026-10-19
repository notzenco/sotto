import FluidAudio
import SottoCore

/// Nil for models Sotto can't run yet. Every Parakeet engine shares `hintBooster`.
func makeEngine(for id: SpeechModelID, spelling: SpellingVariety, hintBooster: HintBooster) -> (any SpeechEngine)? {
    switch id {
    case .parakeetV2: ParakeetFamilyEngine(id: id, version: .v2, booster: hintBooster)
    case .parakeetUltra: ParakeetFamilyEngine(id: id, version: .ultra, booster: hintBooster)
    case .phonon2: ParakeetFamilyEngine(id: id, version: .phonon2, booster: hintBooster)
    case .parakeetV3: ParakeetFamilyEngine(id: id, version: .v3, booster: hintBooster)
    case .cohere: CohereEngine(id: id)
    case .appleEnglish: nil
    }
}
