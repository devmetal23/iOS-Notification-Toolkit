import Foundation
import Testing
import ToolkitCore

/// One row of the detector tables: a realistic notification text and every
/// match expected in it, in order.
struct ContentDetectorCase: Sendable, CustomTestStringConvertible {
    let name: String
    let text: String
    let expected: [ContentDetector.Match]

    init(_ name: String, _ text: String, _ expected: [ContentDetector.Match]) {
        self.name = name
        self.text = text
        self.expected = expected
    }

    var testDescription: String { name }
}

private func codeMatch(_ text: String, _ value: String) -> ContentDetector.Match {
    ContentDetector.Match(kind: .code, text: text, value: value)
}

private func linkMatch(_ text: String, _ value: String? = nil) -> ContentDetector.Match {
    ContentDetector.Match(kind: .link, text: text, value: value ?? text)
}

private func phoneMatch(_ text: String, _ value: String) -> ContentDetector.Match {
    ContentDetector.Match(kind: .phoneNumber, text: text, value: value)
}

@Suite("ContentDetector")
struct ContentDetectorTests {
    // Generated from the same table the Python port of the detector runs.
    static let codeCases: [ContentDetectorCase] = [
        ContentDetectorCase("google prefixed", "G-482913 is your Google verification code.", [codeMatch("G-482913", "482913")]),
        ContentDetectorCase("apple code", "Your Apple Account code is: 482913. Don't share it with anyone.", [codeMatch("482913", "482913")]),
        ContentDetectorCase("whatsapp split dash", "Your WhatsApp code: 123-456\n\nDon't share this code with others", [codeMatch("123-456", "123456")]),
        ContentDetectorCase("split space", "Your Uber code: 123 456. Never share this code.", [codeMatch("123 456", "123456")]),
        ContentDetectorCase("4 digit pin", "Your PIN is 4821", [codeMatch("4821", "4821")]),
        ContentDetectorCase("otp with expiry", "OTP 73914 expires in 10 minutes", [codeMatch("73914", "73914")]),
        ContentDetectorCase("2fa 8 digits", "Your 2FA token is 12345678", [codeMatch("12345678", "12345678")]),
        ContentDetectorCase("one-time", "Use one-time password 9087 to continue", [codeMatch("9087", "9087")]),
        ContentDetectorCase("sign-in", "Sign-in attempt: enter 5521 to continue", [codeMatch("5521", "5521")]),
        ContentDetectorCase("login hyphen keyword", "Login code 0042 for Acme", [codeMatch("0042", "0042")]),
        ContentDetectorCase("code colon no space", "Code:4821", [codeMatch("4821", "4821")]),
        ContentDetectorCase("standalone 6 digit no keyword", "Enter 739104 to finish setting up Acme", [codeMatch("739104", "739104")]),
        ContentDetectorCase("bank otp with amount", "Your OTP for txn of INR 5,000.00 at AMAZON is 482913. Do not share it with anyone.", [codeMatch("482913", "482913")]),
        ContentDetectorCase("bank otp rs card ending", "OTP is 482913 for txn of Rs.5000.00 on card ending 4821. Valid for 10 min.", [codeMatch("482913", "482913")]),
        ContentDetectorCase("code and phone", "Your verification code is 482913. Didn't request it? Call 1-800-555-0100.", [codeMatch("482913", "482913"), phoneMatch("1-800-555-0100", "18005550100")]),
        ContentDetectorCase("duplicate code", "Code 482913. Again, your code is 482913", [codeMatch("482913", "482913")]),
        ContentDetectorCase("prefixed and plain same value", "G-482913 is your code. Enter 482913", [codeMatch("G-482913", "482913")]),
        ContentDetectorCase("keyword plural", "Backup codes: 4821 and 9930", [codeMatch("4821", "4821"), codeMatch("9930", "9930")]),
        ContentDetectorCase("confirm prefix", "Confirmation number 55120", [codeMatch("55120", "55120")]),
        ContentDetectorCase("security keyword", "Security alert: enter 6612 to approve", [codeMatch("6612", "6612")]),
        ContentDetectorCase("keycap emoji not code", "Your code is 4821\u{20E3}", []),
        ContentDetectorCase("emoji with variation selector before code", "Locked🔐\u{FE0F}482913 is your code", [codeMatch("482913", "482913")]),
        ContentDetectorCase("keycap with variation selector not code", "Your code is 4821\u{FE0F}\u{20E3}", []),
        ContentDetectorCase("combining mark not code", "Your code is 4821\u{301}", []),
        ContentDetectorCase("domain bound code", "Your Example code is 482913.\n\n@example.com #482913", [codeMatch("482913", "482913")]),
        ContentDetectorCase("wells fargo 8 digits", "Wells Fargo: Your verification code is 63922817. Don't share it.", [codeMatch("63922817", "63922817")]),
        ContentDetectorCase("code first", "123456 is your Instagram code. Don't share it.", [codeMatch("123456", "123456")]),
        ContentDetectorCase("split 3 3 keyword", "Your verification code is 482 913", [codeMatch("482 913", "482913")]),
    ]

    static let negativeCases: [ContentDetectorCase] = [
        ContentDetectorCase("shipping is not pin", "Order 48213 is shipping", []),
        ContentDetectorCase("spin is not pin", "Spin 4821 times to win", []),
        ContentDetectorCase("year without keyword", "Happy New Year 2026!", []),
        ContentDetectorCase("money", "Payment received: $42.10 from Alex", []),
        ContentDetectorCase("money large", "You spent $1,234.56 at Costco", []),
        ContentDetectorCase("money keyword prefix", "Confirm your payment of $4821", []),
        ContentDetectorCase("money keyword suffix", "Payment of 1500 EUR confirmed", []),
        ContentDetectorCase("percent keyword", "Security update: 4821% faster", []),
        ContentDetectorCase("time", "Meeting moved to 12:30", []),
        ContentDetectorCase("time keyword", "Your login at 12:30 was successful", []),
        ContentDetectorCase("iso date keyword", "Login on 2026-03-08 from Safari", []),
        ContentDetectorCase("us date keyword", "Verification needed by 03/15/2026", []),
        ContentDetectorCase("written date keyword", "New sign-in on March 8, 2026 from iPhone", []),
        ContentDetectorCase("written date dmy keyword", "Security check on 8 March 2026", []),
        ContentDetectorCase("card ending keyword", "Security alert: card ending in 4821 was used", []),
        ContentDetectorCase("masked card keyword", "Security alert: card ****4821 was used", []),
        ContentDetectorCase("order hash", "Order #482913 has shipped", []),
        ContentDetectorCase("5 digits no keyword", "Your table for 2 is ready. Ref 48213", []),
        ContentDetectorCase("ip address keyword", "New login from 203.0.113.45", []),
        ContentDetectorCase("number in url", "Track it at https://example.com/track/482913", [linkMatch("https://example.com/track/482913")]),
        ContentDetectorCase("keyword only in url", "Order 48213 shipped: https://shop.example.com/login", [linkMatch("https://shop.example.com/login")]),
        ContentDetectorCase("alnum token", "Booking ref ABC123456 confirmed", []),
        ContentDetectorCase("lower prefix id", "Your code: item-482913", []),
        ContentDetectorCase("9 digits", "Your code is 123456789", []),
        ContentDetectorCase("decimal", "Pi is about 3.14159", []),
        ContentDetectorCase("thousands", "You earned 4,821 points", []),
        ContentDetectorCase("version", "iOS 27.0.1 is available", []),
        ContentDetectorCase("steps 5 digits", "You walked 12345 steps today", []),
        ContentDetectorCase("chase alert", "Chase: Card ending 4821 - A $42.10 transaction at STARBUCKS on 03/15/2026 at 08:12 AM ET.", []),
        ContentDetectorCase("fedex tracking grouped", "FedEx: Package 7489 2210 4413 scheduled for delivery Tue 3/10", []),
        ContentDetectorCase("fedex tracking grouped keyword", "Confirm delivery of 7489 2210 4413", []),
        ContentDetectorCase("score", "Final: Lakers 112-108 Celtics", []),
        ContentDetectorCase("promo percent", "Use code SAVE20 for 20% off", []),
    ]

    static let linkCases: [ContentDetectorCase] = [
        ContentDetectorCase("https link", "Read more: https://example.com/news?id=42.", [linkMatch("https://example.com/news?id=42")]),
        ContentDetectorCase("bare www", "Visit www.example.com, then reply", [linkMatch("www.example.com", "https://www.example.com")]),
        ContentDetectorCase("link in parens", "Details (https://example.com/a)", [linkMatch("https://example.com/a")]),
        ContentDetectorCase("link balanced parens", "See https://en.wikipedia.org/wiki/Foo_(bar) now", [linkMatch("https://en.wikipedia.org/wiki/Foo_(bar)")]),
        ContentDetectorCase("link quoted", "He said \"https://example.com/x\" right?", [linkMatch("https://example.com/x")]),
        ContentDetectorCase("link trailing punctuation", "Is it http://example.com?!", [linkMatch("http://example.com")]),
        ContentDetectorCase("two links", "https://a.example.com and www.b.example.com", [linkMatch("https://a.example.com"), linkMatch("www.b.example.com", "https://www.b.example.com")]),
        ContentDetectorCase("duplicate link", "https://example.com and again https://example.com", [linkMatch("https://example.com")]),
        ContentDetectorCase("uppercase scheme", "HTTPS://EXAMPLE.COM/A", [linkMatch("HTTPS://EXAMPLE.COM/A")]),
        ContentDetectorCase("bare scheme only", "Type https:// and then the address", []),
        ContentDetectorCase("www inside word", "awww.cute", []),
        ContentDetectorCase("link with emoji after", "Look https://example.com/🎉 wow", [linkMatch("https://example.com/🎉")]),
        ContentDetectorCase("delivery link", "Your package will arrive today between 2:00 PM and 4:00 PM. Track: https://ups.example.com/t/1Z999AA10123456784", [linkMatch("https://ups.example.com/t/1Z999AA10123456784")]),
    ]

    static let phoneCases: [ContentDetectorCase] = [
        ContentDetectorCase("us phone plus parens", "Call +1 (800) 555-0100 for help", [phoneMatch("+1 (800) 555-0100", "+18005550100")]),
        ContentDetectorCase("us phone dashes", "Call 800-555-0100", [phoneMatch("800-555-0100", "8005550100")]),
        ContentDetectorCase("us phone dots", "Text 800.555.0100 to reply", [phoneMatch("800.555.0100", "8005550100")]),
        ContentDetectorCase("us phone parens space", "Office: (800) 555 0100.", [phoneMatch("(800) 555 0100", "8005550100")]),
        ContentDetectorCase("uk phone", "Ring +44 20 7946 0958 today", [phoneMatch("+44 20 7946 0958", "+442079460958")]),
        ContentDetectorCase("french phone", "Appelle-moi au +33 6 12 34 56 78", [phoneMatch("+33 6 12 34 56 78", "+33612345678")]),
        ContentDetectorCase("10 digits bare", "Call me back at 8005550100", [phoneMatch("8005550100", "8005550100")]),
        ContentDetectorCase("plus no separators", "WhatsApp +4915112345678", [phoneMatch("+4915112345678", "+4915112345678")]),
        ContentDetectorCase("7 digit bare not phone", "Call 555-0100 now", []),
        ContentDetectorCase("7 digit bare with keyword is code", "Your code is 555-0100", [codeMatch("555-0100", "5550100")]),
        ContentDetectorCase("list of small numbers", "Lotto: 3 12 25 33 41 7", []),
        ContentDetectorCase("too many digits", "Tracking 9400111899223197428490", []),
        ContentDetectorCase("phone then code", "Call 800-555-0100 or use code 4821", [phoneMatch("800-555-0100", "8005550100"), codeMatch("4821", "4821")]),
        ContentDetectorCase("phone in url", "https://example.com/call/800-555-0100", [linkMatch("https://example.com/call/800-555-0100")]),
        ContentDetectorCase("date dots not phone", "Delivered on 15.03.2026 at 14:30", []),
        ContentDetectorCase("date time not phone", "Updated 2026-03-08 14:30", []),
        ContentDetectorCase("chat mixed", "Hey! Meet at 7:30? My new number is (415) 555-0132 and the menu is at www.cafe.example.com/menu.", [phoneMatch("(415) 555-0132", "4155550132"), linkMatch("www.cafe.example.com/menu", "https://www.cafe.example.com/menu")]),
        ContentDetectorCase("amazon order", "Your order #112-3456789-1234567 has shipped", []),
        ContentDetectorCase("surrogate pairs", "🎉🎉 Code 482913 🎉 https://x.example.com/🎉. 📞 800-555-0100", [codeMatch("482913", "482913"), linkMatch("https://x.example.com/🎉"), phoneMatch("800-555-0100", "8005550100")]),
        ContentDetectorCase("empty", "", []),
    ]

    @Test("Finds one-time codes", arguments: ContentDetectorTests.codeCases)
    func codes(_ testCase: ContentDetectorCase) {
        #expect(ContentDetector.matches(in: testCase.text) == testCase.expected)
    }

    @Test("Ignores numbers that aren't codes", arguments: ContentDetectorTests.negativeCases)
    func nonCodes(_ testCase: ContentDetectorCase) {
        #expect(ContentDetector.matches(in: testCase.text) == testCase.expected)
    }

    @Test("Finds links", arguments: ContentDetectorTests.linkCases)
    func links(_ testCase: ContentDetectorCase) {
        #expect(ContentDetector.matches(in: testCase.text) == testCase.expected)
    }

    @Test("Finds phone numbers", arguments: ContentDetectorTests.phoneCases)
    func phoneNumbers(_ testCase: ContentDetectorCase) {
        #expect(ContentDetector.matches(in: testCase.text) == testCase.expected)
    }

    /// A 4-digit number needs a keyword; whether one is present decides the result.
    @Test("Keywords match whole words, plurals and longer forms", arguments: [
        ("Your pin is 4821", true),
        ("Pins: 4821", true),
        ("Order 4821 is shipping", false),
        ("Spinning 4821", false),
        ("Passcodes 4821", true),
        ("Confirmed 4821", true),
        ("Unconfirmed 4821", false),
        ("Barcode 4821", false),
        ("Decode 4821", false),
        ("Log in with 4821", true),
        ("Sign in: 4821", true),
        ("Signin 4821", true),
        ("One time 4821", true),
        ("2FA 4821", true),
        ("OTPs 4821", true),
        ("Verifying 4821", true),
    ])
    func keywords(text: String, hasCode: Bool) {
        let expected = hasCode ? [codeMatch("4821", "4821")] : []
        #expect(ContentDetector.matches(in: text) == expected)
    }

    @Test("Each kind opens the right URL")
    func urls() {
        let matches = ContentDetector.matches(in: "Code 482913, call +1 (800) 555-0100 or visit www.example.com")
        #expect(matches.map(\.kind) == [.code, .phoneNumber, .link])
        #expect(matches.map(\.url) == [nil, URL(string: "tel:+18005550100"), URL(string: "https://www.example.com")])
        #expect(linkMatch("https://example.com/a?b=1").url?.absoluteString == "https://example.com/a?b=1")
    }

    @Test("IDs combine kind and value")
    func ids() {
        #expect(codeMatch("G-482913", "482913").id == "code-482913")
        #expect(phoneMatch("800-555-0100", "8005550100").id == "phoneNumber-8005550100")
        #expect(linkMatch("www.example.com", "https://www.example.com").id == "link-https://www.example.com")
    }

    @Test("Repeated content comes back once, in text order")
    func orderAndDuplicates() {
        let text = "Code 482913 https://a.example.com 800-555-0100 482913 https://a.example.com 800-555-0100"
        #expect(ContentDetector.matches(in: text) == [
            codeMatch("482913", "482913"),
            linkMatch("https://a.example.com"),
            phoneMatch("800-555-0100", "8005550100"),
        ])
    }

    @Test("Reads an entry's title, subtitle and body")
    func entryFields() {
        let date = Date(timeIntervalSince1970: 1_772_000_000)
        let entry = NotificationEntry(
            id: 1,
            appKey: AppKey(appName: "Acme"),
            appName: "Acme",
            title: "Acme",
            subtitle: "Sign-in",
            body: "Enter 4821 or visit https://acme.example.com",
            receivedAt: date,
            capturedAt: date,
            isTimeSensitive: false
        )
        // The keyword is only in the subtitle.
        #expect(ContentDetector.matches(in: entry) == [codeMatch("4821", "4821"), linkMatch("https://acme.example.com")])
    }

    @Test("Odd input finds nothing and doesn't crash", arguments: [
        String(repeating: "9", count: 5000),
        String(repeating: "🎉", count: 500),
        "www.",
        "+",
        "(((",
        "\u{FEFF}",
        "code " + String(repeating: "1 ", count: 1000),
        "🎉\u{301}4821\u{20E3}\u{FE0F}",
    ])
    func oddInput(_ text: String) {
        #expect(ContentDetector.matches(in: text).isEmpty)
    }

    @Test("Text before a link doesn't stick to it")
    func linkAfterPunctuation() {
        #expect(ContentDetector.matches(in: ")))https://x.example.com") == [linkMatch("https://x.example.com")])
    }
}
