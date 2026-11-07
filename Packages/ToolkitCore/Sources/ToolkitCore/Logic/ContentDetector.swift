import Foundation

/// Finds one-time codes, links and phone numbers in notification text (FR-11).
///
/// Uses `NSRegularExpression` and string APIs only (no `NSDataDetector`), so it
/// runs on Linux. The text is scanned three times: links, then phone numbers,
/// then codes. Each pass skips text an earlier one claimed, so the digits of a
/// URL or phone number never come back as a code.
public enum ContentDetector {
    public enum Kind: Hashable, Sendable {
        /// A verification or login code, e.g. "482913" or "G-482913".
        case code
        case link
        case phoneNumber
    }

    public struct Match: Hashable, Sendable, Identifiable {
        public var kind: Kind
        /// The text as it appears in the notification.
        public var text: String
        /// Normalized value to act on: the code without spaces, the URL, or the dialable number.
        public var value: String

        public var id: String { "\(kind)-\(value)" }

        public init(kind: Kind, text: String, value: String) {
            self.kind = kind
            self.text = text
            self.value = value
        }

        /// A `tel:` or web URL for opening, nil for codes.
        public var url: URL? {
            switch kind {
            case .code: nil
            case .link: URL(string: value)
            case .phoneNumber: URL(string: "tel:\(value)")
            }
        }
    }

    /// Matches in the order they appear, without duplicates.
    public static func matches(in text: String) -> [Match] {
        guard !text.isEmpty else { return [] }
        let scan = TextScan(text)
        let fullRange = NSRange(text.startIndex..., in: text)
        var found: [Found] = []
        var claimed: [NSRange] = []

        // Links.
        for result in linkRegex.matches(in: text, range: fullRange) {
            guard let bounds = Range(result.range, in: text) else { continue }
            let link = trimmingTrailingPunctuation(text[bounds])
            guard let value = linkValue(link) else { continue }
            let range = NSRange(location: result.range.location, length: link.utf16.count)
            claimed.append(range)
            found.append(Found(location: range.location, match: Match(kind: .link, text: String(link), value: value)))
        }
        let linkRanges = claimed

        // Phone numbers.
        for result in phoneRegex.matches(in: text, range: fullRange) {
            let range = result.range
            guard !overlaps(range, claimed),
                  isStandalonePhone(range, in: scan),
                  let bounds = Range(range, in: text),
                  let value = phoneValue(text[bounds])
            else { continue }
            claimed.append(range)
            found.append(Found(location: range.location, match: Match(kind: .phoneNumber, text: String(text[bounds]), value: value)))
        }

        // Codes. Keywords inside links ("…/login") don't count.
        let hasKeyword = containsCodeKeyword(scan.text(blanking: linkRanges))
        for result in codeRegex.matches(in: text, range: fullRange) {
            let range = result.range
            guard let token = codeToken(of: result), token != .ignored,
                  !overlaps(range, claimed),
                  isStandaloneCode(range, in: scan),
                  let bounds = Range(range, in: text)
            else { continue }
            let codeText = text[bounds]
            let digits = String(codeText.filter { $0.isASCII && $0.isNumber })
            guard (4...8).contains(digits.count) else { continue }
            // Without a keyword only an unsplit 6-digit number ("G-482913" counts) is a code.
            guard hasKeyword || (digits.count == 6 && token != .split) else { continue }
            found.append(Found(location: range.location, match: Match(kind: .code, text: String(codeText), value: digits)))
        }

        var seen = Set<String>()
        return found
            .sorted { $0.location < $1.location }
            .map { $0.match }
            .filter { seen.insert($0.id).inserted }
    }

    public static func matches(in entry: NotificationEntry) -> [Match] {
        matches(in: [entry.title, entry.subtitle, entry.body].filter { !$0.isEmpty }.joined(separator: "\n"))
    }
}

// MARK: - Patterns

// Every pattern sticks to syntax ICU (NSRegularExpression) and Python `re` share,
// with ASCII digits only. Never start a character class with ":" (ICU reads "[:"
// as a POSIX class) and escape "$" inside classes.
extension ContentDetector {
    /// `http(s)://…` or bare `www.…`, up to whitespace, `<`, `>` or `"`.
    nonisolated(unsafe) private static let linkRegex = makeRegex(#"(?i)\b(?:https?://|www\.)[^\s<>"]+"#)

    /// Digit groups of up to 5 digits, an optional leading `+`, at most one
    /// separator (space, dot or dash) between groups, and groups in parentheses.
    /// Only a starting point: `phoneValue` decides what is a phone number.
    nonisolated(unsafe) private static let phoneRegex = makeRegex(
        #"\+?(?:\([0-9]{1,5}\)|[0-9]{1,5})(?:[ .\-]?(?:\([0-9]{1,5}\)|[0-9]{1,5})){0,7}"#
    )

    /// One alternative per token, each its own capture group (no other capturing
    /// groups), tried in order. `.ignored` alternatives consume numbers that are
    /// not codes (money, dates, times, card endings) so their digits can't match later.
    nonisolated(unsafe) private static let codeRegex = makeRegex(
        codeAlternatives.map { "(" + $0.pattern + ")" }.joined(separator: "|")
    )

    // fileprivate, not private: used in signatures across this file's extensions.
    fileprivate enum CodeToken {
        case ignored
        /// Letters, a dash and digits: "G-482913".
        case prefixed
        /// Two groups of 3–4 digits split by a space or dash: "123 456".
        case split
        case plain
    }

    private static let month =
        #"(?i:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"#
    private static let currencyBefore = #"(?i:usd|eur|gbp|cad|aud|nzd|chf|jpy|cny|inr|mxn|brl|sek|nok|dkk|rs\.?)"#
    private static let currencyAfter =
        #"(?i:usd|eur|gbp|cad|aud|nzd|chf|jpy|cny|inr|mxn|brl|sek|nok|dkk|dollars?|euros?|pounds?|bucks)"#

    // Composite patterns, built here so the alternatives list stays a plain literal.
    private static let amountAfterCurrencyCode: String = #"\b"# + currencyBefore + #"\s?[0-9][0-9,.]*"#
    private static let amountBeforeCurrency: String = #"[0-9][0-9,.]*\s?(?:[\$€£¥₹%]|"# + currencyAfter + #"\b)"#
    private static let monthDayYear: String =
        #"\b"# + month + #"\b\.?(?:\s+[0-9]{1,2}(?i:st|nd|rd|th)?,?)?\s+(?:19|20)[0-9]{2}\b"#
    private static let dayMonthYear: String = #"\b[0-9]{1,2}(?i:st|nd|rd|th)?\s+"# + month + #"\b\.?,?\s+(?:19|20)[0-9]{2}\b"#

    private static let codeAlternatives: [(token: CodeToken, pattern: String)] = [
        // $42.10, € 1.200
        (.ignored, #"[\$€£¥₹]\s?[0-9][0-9,.]*"#),
        // USD 1500, Rs.5000.00
        (.ignored, amountAfterCurrencyCode),
        // 1500 EUR, 20 dollars, 15%
        (.ignored, amountBeforeCurrency),
        // ****4821, •••• 4821, ...4821
        (.ignored, #"(?:[\*•xX]{2,}\s?|\.{2,}|…)[0-9]{2,}"#),
        // card ending in 4821
        (.ignored, #"\b(?i:ending|ends)(?:\s+(?i:in|with))?\s*[#\:]?\s*[0-9]+"#),
        // March 8, 2026 · Mar 2026
        (.ignored, monthDayYear),
        // 8 March 2026
        (.ignored, dayMonthYear),
        // 12:30, 03/15/2026, 15.03.2026, 4,821, 3.14
        (.ignored, #"[0-9]+(?:[.,:/][0-9]+)+"#),
        // 2026-03-08, 112-3456789-1234567
        (.ignored, #"[0-9]+(?:-[0-9]+){2,}"#),
        // 7489 2210 4413 (tracking and card numbers)
        (.ignored, #"[0-9]{3,4}(?: [0-9]{3,4}){2,}"#),
        (.prefixed, #"[A-Z]{1,3}-[0-9]{4,8}"#),
        (.split, #"[0-9]{3,4}[ \-][0-9]{3,4}"#),
        (.plain, #"[0-9]+"#),
    ]

    /// Each keyword is a run of whole words; text is split into words at anything
    /// but letters and digits, so "sign-in" also matches "Sign in".
    private static let codeKeywords: [[String]] = [
        ["code"], ["otp"], ["passcode"], ["pin"], ["verification"], ["verify"], ["2fa"],
        ["one", "time"], ["onetime"], ["login"], ["log", "in"], ["sign", "in"], ["signin"],
        ["security"], ["confirm"],
    ]

    private static let linkTrailingPunctuation: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "\"", "'"]
    private static let currencySymbols: Set<Unicode.Scalar> = ["$", "€", "£", "¥", "₹"]
    /// A number right after one of these is part of a tag, path, query or sum.
    private static let rejectedBefore: Set<Unicode.Scalar> = ["#", "/", "@", "=", "&", "\\", "+"]

    private static func makeRegex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid ContentDetector pattern \(pattern): \(error)")
        }
    }
}

// MARK: - Rules

extension ContentDetector {
    fileprivate struct Found {
        var location: Int
        var match: Match
    }

    private static func overlaps(_ range: NSRange, _ others: [NSRange]) -> Bool {
        others.contains { range.location < $0.location + $0.length && $0.location < range.location + range.length }
    }

    private static func codeToken(of result: NSTextCheckingResult) -> CodeToken? {
        for group in 1..<max(result.numberOfRanges, 1) where result.range(at: group).location != NSNotFound {
            return group <= codeAlternatives.count ? codeAlternatives[group - 1].token : nil
        }
        return nil
    }

    /// Drops trailing `.,;:!?)]"'`, keeping a `)` or `]` that closes one inside the link.
    private static func trimmingTrailingPunctuation(_ link: Substring) -> Substring {
        var link = link
        while let last = link.last, linkTrailingPunctuation.contains(last) {
            if last == ")", link.filter({ $0 == "(" }).count >= link.filter({ $0 == ")" }).count { break }
            if last == "]", link.filter({ $0 == "[" }).count >= link.filter({ $0 == "]" }).count { break }
            link = link.dropLast()
        }
        return link
    }

    /// The URL to open, with `https://` added to bare `www.` links. Nil when
    /// nothing follows the scheme or `www.`.
    private static func linkValue(_ link: Substring) -> String? {
        let lowercased = link.lowercased()
        let schemeLength = lowercased.hasPrefix("https://") ? 8 : lowercased.hasPrefix("http://") ? 7 : 0
        let host = link.dropFirst(schemeLength == 0 ? 4 : schemeLength)
        guard isWordScalar(host.unicodeScalars.first) else { return nil }
        return schemeLength == 0 ? "https://" + String(link) : String(link)
    }

    /// The dialable number (digits, with a leading `+` if present), or nil when
    /// the candidate isn't shaped like a phone number.
    private static func phoneValue(_ phone: Substring) -> String? {
        let groups = phone.split(whereSeparator: { !($0.isASCII && $0.isNumber) })
        let digits = groups.joined()
        guard (7...15).contains(digits.count) else { return nil }
        let lengths = groups.map { $0.count }
        // "+1 …" and "+33 6 …" have one single-digit group; "3 12 25 33 41 7" is a list.
        guard lengths.filter({ $0 == 1 }).count <= 1 else { return nil }
        let hasPlus = phone.hasPrefix("+")
        if !hasPlus {
            // Without separators it takes 10 digits ("8005550100").
            if lengths.count == 1 && digits.count < 10 { return nil }
            if !phone.contains("(") {
                // "555-0100" or "1234 5678": a split code, not a phone number.
                if lengths.count == 2 && digits.count < 10 { return nil }
                if isDateShaped(lengths) { return nil }
                // An IPv4 address.
                if lengths.count == 4 && lengths.allSatisfy({ $0 <= 3 }) && phone.filter({ $0 == "." }).count == 3 { return nil }
                // A tracking or card number in blocks of four.
                if lengths.count >= 3 && lengths.allSatisfy({ $0 == 4 }) { return nil }
            }
        }
        return (hasPlus ? "+" : "") + digits
    }

    /// 2026-03-08, 15.03.2026, 03-15-26.
    private static func isDateShaped(_ lengths: [Int]) -> Bool {
        guard lengths.count == 3 else { return false }
        let (first, second, third) = (lengths[0], lengths[1], lengths[2])
        return (first == 4 && second <= 2 && third <= 2) || (first <= 2 && second <= 2 && (third == 2 || third == 4))
    }

    /// Not glued to a word, currency symbol, tag or a larger number like "12:30" or "1.5".
    private static func isStandalonePhone(_ range: NSRange, in scan: TextScan) -> Bool {
        let (previous, beforePrevious) = scan.scalars(before: range.location)
        if isWordScalarBefore(previous) || isOneOf(previous, rejectedBefore) || isOneOf(previous, currencySymbols) { return false }
        if isOneOf(previous, ["-", ".", ",", ":"]) && isDigit(beforePrevious) { return false }
        let (next, afterNext) = scan.scalars(after: range.location + range.length)
        if isWordScalar(next) || next == "%" { return false }
        if isOneOf(next, [".", ",", ":", "/", "-"]) && isDigit(afterNext) { return false }
        return true
    }

    /// Like `isStandalonePhone`, and also not part of an identifier like "item-4821".
    private static func isStandaloneCode(_ range: NSRange, in scan: TextScan) -> Bool {
        let (previous, beforePrevious) = scan.scalars(before: range.location)
        if isWordScalarBefore(previous) || isOneOf(previous, rejectedBefore) || isOneOf(previous, currencySymbols) { return false }
        if isOneOf(previous, ["-", "."]) && isWordScalar(beforePrevious) { return false }
        if isOneOf(previous, [",", ":"]) && isDigit(beforePrevious) { return false }
        let (next, afterNext) = scan.scalars(after: range.location + range.length)
        if isWordScalar(next) || next == "%" { return false }
        if isOneOf(next, ["-", "/"]) && isWordScalar(afterNext) { return false }
        if isOneOf(next, [".", ",", ":"]) && isDigit(afterNext) { return false }
        return true
    }

    private static func containsCodeKeyword(_ text: String) -> Bool {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for start in words.indices {
            for keyword in codeKeywords where start + keyword.count <= words.count {
                let lastPart = keyword.count - 1
                let leadingPartsMatch = (0..<lastPart).allSatisfy { words[start + $0] == keyword[$0] }
                if leadingPartsMatch && isKeywordForm(words[start + lastPart], of: keyword[lastPart]) {
                    return true
                }
            }
        }
        return false
    }

    /// The keyword itself, its plural, or for keywords of 4+ letters any word
    /// starting with it ("codes", "confirmation"). "pin" never matches "shipping".
    private static func isKeywordForm(_ word: Substring, of keyword: String) -> Bool {
        word == keyword || word == keyword + "s" || (keyword.count >= 4 && word.hasPrefix(keyword))
    }

    /// Letters, numbers, `_` and combining marks. A mark after a digit (a keycap
    /// emoji, an accent) makes it part of something else.
    private static func isWordScalar(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        let properties = scalar.properties
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark:
            return true
        default:
            return properties.isAlphabetic || properties.numericType != nil || scalar == "_"
        }
    }

    /// `isWordScalar` for the character before a match. A variation selector
    /// there only ends an emoji, so "🔐️482913" still has a code.
    private static func isWordScalarBefore(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar, !(0xFE00...0xFE0F).contains(scalar.value) else { return false }
        return isWordScalar(scalar)
    }

    private static func isDigit(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return (0x30...0x39).contains(scalar.value)
    }

    private static func isOneOf(_ scalar: Unicode.Scalar?, _ set: Set<Unicode.Scalar>) -> Bool {
        guard let scalar else { return false }
        return set.contains(scalar)
    }
}

// MARK: - UTF-16 scanning

/// The text's UTF-16 code units, which `NSRange` offsets index, with lookups
/// that decode surrogate pairs and never return half of one.
private struct TextScan {
    let units: [UInt16]

    init(_ text: String) {
        units = Array(text.utf16)
    }

    /// The scalar ending at `offset` and the one before it.
    func scalars(before offset: Int) -> (Unicode.Scalar?, Unicode.Scalar?) {
        guard let previous = scalar(endingAt: offset) else { return (nil, nil) }
        return (previous.scalar, scalar(endingAt: previous.start)?.scalar)
    }

    /// The scalar starting at `offset` and the one after it.
    func scalars(after offset: Int) -> (Unicode.Scalar?, Unicode.Scalar?) {
        guard let next = scalar(at: offset) else { return (nil, nil) }
        return (next, scalar(at: offset + (next.value > 0xFFFF ? 2 : 1)))
    }

    /// The text with the given ranges replaced by spaces.
    func text(blanking ranges: [NSRange]) -> String {
        var copy = units
        for range in ranges {
            for offset in range.location..<(range.location + range.length) where offset < copy.count {
                copy[offset] = 0x20
            }
        }
        return String(decoding: copy, as: UTF16.self)
    }

    /// Nil outside the text, or on half of a surrogate pair.
    private func scalar(at offset: Int) -> Unicode.Scalar? {
        guard offset >= 0, offset < units.count else { return nil }
        let unit = units[offset]
        guard UTF16.isLeadSurrogate(unit) else {
            return Unicode.Scalar(unit) // nil for a trail surrogate
        }
        guard offset + 1 < units.count, UTF16.isTrailSurrogate(units[offset + 1]) else { return nil }
        let lead = UInt32(unit) - 0xD800
        let trail = UInt32(units[offset + 1]) - 0xDC00
        return Unicode.Scalar(0x10000 + (lead << 10) + trail)
    }

    private func scalar(endingAt offset: Int) -> (scalar: Unicode.Scalar, start: Int)? {
        guard offset > 0, offset <= units.count else { return nil }
        let isPair = offset >= 2 && UTF16.isTrailSurrogate(units[offset - 1]) && UTF16.isLeadSurrogate(units[offset - 2])
        let start = isPair ? offset - 2 : offset - 1
        guard let found = scalar(at: start) else { return nil }
        return (found, start)
    }
}
