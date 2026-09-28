import Foundation

/// The initial drawn in the small disc on a pinned folder's cover (the chip no longer
/// carries a name row). Pure so the rules are unit-tested; the chip only renders the result.
///
/// Automatic rule: a CJK name gives its first character; a Latin name gives one capital
/// letter, or the first letters of its first two words ("Final Cut" → "FC"); an emoji or
/// symbol lead is kept as-is. A user-set badge overrides it, capped at two characters.
enum FolderBadgeText {
    /// Longest badge in grapheme clusters: two Latin letters or one emoji still fit the disc.
    static let maximumLength = 2

    static func resolve(name: String, custom: String?) -> String {
        if let custom = sanitizedCustom(custom) { return custom }
        return automatic(for: name)
    }

    /// Trimmed and capped at `maximumLength` graphemes; blank means "no override".
    static func sanitizedCustom(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumLength))
    }

    static func automatic(for name: String) -> String {
        let words = name
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .map { $0.drop(while: isLeadingNoise) }
            .filter { !$0.isEmpty }
        guard let first = words.first?.first else {
            return name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0) } ?? "?"
        }
        if isPictographic(first) || isCJK(first) { return String(first) }
        var initials = capital(first)
        if words.count > 1, let second = words[1].first,
           !isCJK(second), !isPictographic(second),
           second.isLetter || second.isNumber {
            initials += capital(second)
        }
        return initials
    }

    /// Punctuation a folder name often starts with (".config", "_Archive", "[Work]", "~Temp")
    /// says nothing about which folder it is.
    private static func isLeadingNoise(_ character: Character) -> Bool {
        !(character.isLetter || character.isNumber || isPictographic(character))
    }

    private static func capital(_ character: Character) -> String {
        // "ß".uppercased() is "SS"; one letter is the contract.
        String(String(character).uppercased().prefix(1))
    }

    private static func isPictographic(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        // `isEmoji` alone is true for digits and "#"; require an emoji presentation or a sequence.
        return scalar.properties.isEmojiPresentation
            || (scalar.properties.isEmoji && character.unicodeScalars.count > 1)
    }

    private static func isCJK(_ character: Character) -> Bool {
        guard let value = character.unicodeScalars.first?.value else { return false }
        switch value {
        case 0x2E80...0x2FDF,   // CJK radicals
             0x3040...0x30FF,   // Hiragana, Katakana
             0x3100...0x312F,   // Bopomofo
             0x3400...0x4DBF,   // CJK extension A
             0x4E00...0x9FFF,   // CJK unified ideographs
             0xAC00...0xD7AF,   // Hangul syllables
             0xF900...0xFAFF,   // CJK compatibility ideographs
             0x20000...0x3134F: // CJK extensions B–G
            return true
        default:
            return false
        }
    }
}
