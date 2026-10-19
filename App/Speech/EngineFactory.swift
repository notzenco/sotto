import FluidAudio
import SottoCore

/// Nil for models Sotto can't run yet.
func makeEngine(for id: SpeechModelID, spelling: SpellingVariety) -> (any SpeechEngine)? {
    switch id {
    case .parakeetV2: ParakeetFamilyEngine(id: id, version: .v2)
    case .parakeetUltra: ParakeetFamilyEngine(id: id, version: .ultra)
    case .phonon2: ParakeetFamilyEngine(id: id, version: .phonon2)
    case .parakeetV3: ParakeetFamilyEngine(id: id, version: .v3)
    case .cohere: nil
    case .appleEnglish: nil
    }
}
