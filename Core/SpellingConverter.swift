import Foundation

/// Respells prose word by word between American, British and Australian
/// English, leaving anything that looks like code alone.
public enum SpellingConverter {
    /// Credit for the bundled word list, which its licence asks About to show.
    public static let credit: String? = "Spelling list adapted from VarCon by Kevin Atkinson and Benjamin Titze, from word lists by Geoff Kuenning. Copyright 2000-2019 Kevin Atkinson, 2016 Benjamin Titze, 1993 Geoff Kuenning. Modified: a subset of common words."

    /// The word list's full licence notice, as its header gives it, for About.
    public static let licenceNotice = """
        Copyright 2000-2019 by Kevin Atkinson

        Permission to use, copy, modify, distribute and sell this array, the
        associated software, and its documentation for any purpose is hereby
        granted without fee, provided that the above copyright notice appears
        in all copies and that both that copyright notice and this permission
        notice appear in supporting documentation. Kevin Atkinson makes no
        representations about the suitability of this array for any
        purpose. It is provided "as is" without express or implied warranty.

        Copyright 2016 by Benjamin Titze

        Permission to use, copy, modify, distribute and sell this array, the
        associated software, and its documentation for any purpose is hereby
        granted without fee, provided that the above copyright notice appears
        in all copies and that both that copyright notice and this permission
        notice appear in supporting documentation. Benjamin Titze makes no
        representations about the suitability of this array for any
        purpose. It is provided "as is" without express or implied warranty.

        Since the original words lists come from the Ispell distribution:

        Copyright 1993, Geoff Kuenning, Granada Hills, CA
        All rights reserved.

        Redistribution and use in source and binary forms, with or without
        modification, are permitted provided that the following conditions
        are met:

        1. Redistributions of source code must retain the above copyright
           notice, this list of conditions and the following disclaimer.
        2. Redistributions in binary form must reproduce the above copyright
           notice, this list of conditions and the following disclaimer in the
           documentation and/or other materials provided with the distribution.
        3. All modifications to the source code must be clearly marked as
           such.  Binary redistributions based on modified source code
           must be clearly marked as modified versions in the documentation
           and/or other materials provided with the distribution.
        (clause 4 removed with permission from Geoff Kuenning)
        5. The name of Geoff Kuenning may not be used to endorse or promote
           products derived from this software without specific prior
           written permission.

        THIS SOFTWARE IS PROVIDED BY GEOFF KUENNING AND CONTRIBUTORS ``AS IS'' AND
        ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
        IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
        ARE DISCLAIMED.  IN NO EVENT SHALL GEOFF KUENNING OR CONTRIBUTORS BE LIABLE
        FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
        DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
        OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
        HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
        LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
        OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
        SUCH DAMAGE.
        """

    public static func convert(_ text: String, to variety: SpellingVariety) -> String {
        let table = switch variety {
        case .australian: australian
        case .british: SpellingTable.americanToBritish
        case .american: american
        }
        var output = ""
        var chunk = ""
        var inBackticks = false
        for character in text {
            if character == "`" {
                output += respell(chunk, with: table)
                chunk = ""
                inBackticks.toggle()
                output.append(character)
            } else if inBackticks {
                output.append(character)
            } else if character.isWhitespace {
                output += respell(chunk, with: table)
                chunk = ""
                output.append(character)
            } else {
                chunk.append(character)
            }
        }
        return output + respell(chunk, with: table)
    }

    private static let australian = SpellingTable.americanToBritish.filter {
        !SpellingTable.australianKeeps.contains($0.key)
    }

    // The generator only keeps pairs that are unambiguous both ways, so
    // every British spelling maps back to exactly one American one.
    private static let american = Dictionary(
        SpellingTable.americanToBritish.map { ($0.value, $0.key) },
        uniquingKeysWith: { first, _ in first }
    )

    /// Respells the words in one whitespace-free chunk, keeping its punctuation.
    private static func respell(_ chunk: String, with table: [String: String]) -> String {
        guard !chunk.isEmpty, !looksLikeCode(chunk) else { return chunk }
        var output = ""
        var word = ""
        for character in chunk {
            if character.isLetter {
                word.append(character)
            } else {
                output += respellWord(word, with: table)
                word = ""
                output.append(character)
            }
        }
        return output + respellWord(word, with: table)
    }

    /// Matches case as lower or Capitalised; any other casing, including
    /// all caps, is left unchanged.
    private static func respellWord(_ word: String, with table: [String: String]) -> String {
        let lower = word.lowercased()
        guard let target = table[lower] else { return word }
        if word == lower { return target }
        if word.dropFirst() == lower.dropFirst(), word.first?.isUppercase == true {
            return target.prefix(1).uppercased() + target.dropFirst()
        }
        return word
    }

    /// Paths, URLs, snake_case, camelCase, dotted names such as file.color,
    /// flags, tags, variables, handles and anything with a digit.
    private static func looksLikeCode(_ chunk: String) -> Bool {
        if chunk.contains(where: { $0 == "_" || $0 == "/" || $0 == "\\" || $0.isNumber }) { return true }
        if ["--", "#", "$", "@"].contains(where: chunk.hasPrefix) { return true }
        var previous: Character?
        var beforePrevious: Character?
        for character in chunk {
            if let previous, previous.isLowercase, character.isUppercase { return true }
            if let beforePrevious, let previous, previous == ".", beforePrevious.isLetter, character.isLetter {
                return true
            }
            beforePrevious = previous
            previous = character
        }
        return false
    }
}
