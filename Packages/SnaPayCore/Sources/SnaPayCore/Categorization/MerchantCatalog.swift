import Foundation

/// Recognizes well-known merchants (Israeli chains and common international ones), the way a
/// card company's statement labels them "סופר" or "תעופה", so a payment gets a category before
/// the household ever filed that merchant.
public enum MerchantCatalog {
    /// What a merchant sells, matched to the user's own categories by `category(for:in:)`.
    public enum Kind: String, CaseIterable, Sendable {
        case food, coffee, groceries, shopping, car, transport, housing, bills, telecom, health
        case entertainment, travel, gifts, kids, pets, education
    }

    /// The kind for a merchant name, or `nil` for one the catalog doesn't know. The longest
    /// matching entry wins, so "סופר פארם" is health while "סופר" alone would be groceries.
    public static func kind(for merchant: String) -> Kind? {
        let words = MerchantCatalog.words(of: merchant)
        guard !words.isEmpty else { return nil }
        var best: (kind: Kind, length: Int)?
        for entry in entries where entry.length > (best?.length ?? 0) {
            if contains(words, entry.words) {
                best = (entry.kind, entry.length)
            }
        }
        return best?.kind
    }

    /// The user's category for a kind: the default category's emoji first, then a word in its
    /// name, so it still works after the user renamed "אוכל ומסעדות" to "אוכל". Coffee falls
    /// back to food when there's no coffee category.
    public static func category(for kind: Kind, in categories: [CategoryItem]) -> CategoryItem? {
        let usable = categories.filter { $0.kind == .expense && !$0.isArchived && !$0.isTrip }
        let hint = hints[kind]!
        if let byEmoji = usable.first(where: { hint.emoji.contains($0.emoji) }) { return byEmoji }
        if let byName = usable.first(where: { category in hint.words.contains { category.name.contains($0) } }) {
            return byName
        }
        return kind == .coffee ? category(for: .food, in: categories) : nil
    }

    /// The user's category for a merchant the catalog knows.
    public static func category(forMerchant merchant: String, in categories: [CategoryItem]) -> CategoryItem? {
        kind(for: merchant).flatMap { category(for: $0, in: categories) }
    }

    // MARK: Matching

    private struct Entry {
        let words: [String]
        let kind: Kind
        /// Letters in the pattern, to prefer the most specific match.
        let length: Int
    }

    /// Lowercased words, splitting on punctuation too, so "סופר-פארם" and "H&M" read as two
    /// words ("סופר פארם", "h m") and "Booking.com" as "booking com".
    private static func words(of text: String) -> [String] {
        let spaced = String(text.map { $0.isLetter || $0.isWhitespace ? $0 : " " })
        return CategorySuggester.normalize(spaced).split(separator: " ").map(String.init)
    }

    /// Whether `pattern` appears as consecutive words of `words`. A pattern word of four letters
    /// or more also matches as a prefix ("מסעד" → "מסעדת"); shorter ones must match exactly.
    private static func contains(_ words: [String], _ pattern: [String]) -> Bool {
        guard !pattern.isEmpty, pattern.count <= words.count else { return false }
        for start in 0...(words.count - pattern.count) {
            let matches = pattern.indices.allSatisfy { i in
                let word = words[start + i], part = pattern[i]
                return word == part || (part.count >= 4 && word.hasPrefix(part))
            }
            if matches { return true }
        }
        return false
    }

    private static let entries: [Entry] = patterns.flatMap { kind, names in
        names.compactMap { name -> Entry? in
            let words = MerchantCatalog.words(of: name)
            guard !words.isEmpty else { return nil }
            return Entry(words: words, kind: kind, length: words.reduce(0) { $0 + $1.count })
        }
    }

    private static let hints: [Kind: (emoji: Set<String>, words: [String])] = [
        .food: (["🍔", "🍕", "🍣", "🥗"], ["אוכל", "מסעד"]),
        .coffee: (["☕"], ["קפה"]),
        .groceries: (["🛒"], ["סופר", "מכולת"]),
        .shopping: (["🛍️", "👗", "👟"], ["קניות", "ביגוד"]),
        .car: (["🚗", "⛽", "🅿️"], ["רכב", "דלק"]),
        .transport: (["🚌", "🚕"], ["תחבורה", "מוניות"]),
        .housing: (["🏠", "🛋️"], ["דיור", "שכירות"]),
        .bills: (["💡", "💧", "🔥"], ["חשבונות"]),
        .telecom: (["📱"], ["תקשורת", "סלולר"]),
        .health: (["💊", "🏥", "🦷"], ["בריאות", "פארם"]),
        .entertainment: (["🎬", "🎮", "🎵", "🍺"], ["בילוי", "בידור"]),
        .travel: (["✈️", "🏨", "🏖️"], ["טיול", "חופש", "נסיעות"]),
        .gifts: (["🎁", "💐"], ["מתנ"]),
        .kids: (["👶", "🧸"], ["ילד"]),
        .pets: (["🐾"], ["חיות", "כלב", "חתול"]),
        .education: (["📚", "🎓", "✏️"], ["לימוד", "חינוך"]),
    ]

    /// Names as they show on Apple Pay (Hebrew and English), normalized like merchants.
    private static let patterns: [(Kind, [String])] = [
        (.groceries, [
            "שופרסל", "shufersal", "רמי לוי", "rami levy", "ויקטורי", "victory", "יוחננוף", "yochananof",
            "אושר עד", "osher ad", "טיב טעם", "tiv taam", "יינות ביתן", "yeinot bitan", "חצי חינם", "hazi hinam",
            "קרפור", "carrefour", "מגה בעיר", "am pm", "ampm", "סטופ מרקט", "stop market", "פרש מרקט", "fresh market",
            "קשת טעמים", "keshet teamim", "זול ובגדול", "ניצת הדובדבן", "מכולת", "סופרמרקט", "supermarket",
            "מינימרקט", "minimarket", "מעדני", "ירקות", "ירקן", "קצביה", "מאפיה", "bakery",
        ]),
        (.food, [
            "wolt", "וולט", "תן ביס", "ten bis", "tenbis", "cibus", "סיבוס", "mishloha", "משלוחה",
            "מקדונלדס", "mcdonalds", "mcdonald", "בורגר קינג", "burger king", "בורגראנץ", "burgeranch", "ברגר ראנץ",
            "דומינוס", "domino", "dominos", "פיצה האט", "pizza hut", "kfc", "מסעדת", "מסעדה", "restaurant",
            "פיצה", "pizza", "פיצרייה", "pizzeria", "שווארמה", "shawarma", "פלאפל", "falafel", "חומוס", "hummus",
            "סושי", "sushi", "גפניקה", "japanika", "מוזס", "moses", "אגדיר", "agadir", "גירף", "giraffe",
            "בורגר", "burger", "גריל", "grill", "סטייקיה", "steakhouse", "שניצל", "קונדיטוריה", "גלידה", "gelato",
        ]),
        (.coffee, [
            "ארומה", "aroma", "קופיקס", "cofix", "סטארבקס", "starbucks", "קפה גרג", "cafe greg", "greg",
            "לנדוור", "landwer", "קפה קפה", "cafe cafe", "קפה", "cafe", "coffee", "espresso", "אספרסו",
        ]),
        (.car, [
            "פז", "paz", "סונול", "sonol", "דלק", "delek", "דור אלון", "dor alon", "תחנת דלק",
            "פנגו", "pango", "סלופארק", "cellopark", "חניון", "חניה", "parking", "כביש", "derech eretz",
            "מוסך", "garage", "שטיפת רכב", "car wash", "carwash", "צמיגים", "רישוי",
        ]),
        (.transport, [
            "רב קו", "rav kav", "ravkav", "גט", "gett", "uber", "יאנגו", "yango", "bolt", "רכבת ישראל",
            "israel railways", "אגד", "egged", "מטרופולין", "metropoline", "אפיקים", "afikim", "מוביט", "moovit",
            "מונית", "taxi", "דן אזור",
        ]),
        (.travel, [
            "אל על", "el al", "elal", "ישראייר", "israir", "ארקיע", "arkia", "booking", "airbnb", "expedia",
            "agoda", "hotels", "hotel", "מלון", "ryanair", "wizz", "easyjet", "lufthansa", "turkish airlines",
            "airlines", "airways", "airline", "duty free", "james richardson", "דיוטי פרי", "rentalcars",
            "hertz", "avis", "sixt", "rent a car", "השכרת רכב", "אלדן", "eldan", "שלמה סיקסט", "מלונות דן", "dan hotels",
        ]),
        (.health, [
            "סופר פארם", "super pharm", "superpharm", "בי פארם", "be pharm", "גוד פארם", "good pharm", "פארם",
            "pharm", "pharmacy", "בית מרקחת", "כללית", "clalit", "מכבי", "maccabi", "מאוחדת", "meuhedet",
            "לאומית שירותי בריאות", "רופא", "doctor", "מרפאה", "clinic", "שיניים", "dental", "אופטיקה", "optic",
            "optica",
        ]),
        (.telecom, [
            "פרטנר", "partner", "סלקום", "cellcom", "פלאפון", "pelephone", "הוט מובייל", "hot mobile",
            "בזק", "bezeq", "גולן טלקום", "golan telecom", "רמי לוי תקשורת", "סמייל",
        ]),
        (.bills, [
            "חברת החשמל", "חברת חשמל", "israel electric", "iec", "מקורות", "תאגיד", "ארנונה", "עיריית", "עירית",
            "municipality", "סופרגז", "supergas", "אמישראגז", "amisragas", "פזגז", "pazgas", "ביטוח", "insurance",
        ]),
        (.entertainment, [
            "סינמה סיטי", "cinema city", "יס פלאנט", "yes planet", "רב חן", "rav hen", "cinema", "קולנוע",
            "netflix", "נטפליקס", "spotify", "ספוטיפיי", "disney", "steam", "playstation", "xbox", "nintendo",
            "eventim", "לאן", "leaan", "תיאטרון", "theater", "theatre", "פאב", "pub", "הופעה",
            "כרטיסים", "tickets", "בולינג", "bowling",
        ]),
        (.shopping, [
            "זארה", "zara", "איקאה", "ikea", "קסטרו", "castro", "פוקס", "fox", "רנואר", "renuar",
            "אמריקן איגל", "american eagle", "טרמינל איקס", "terminal x", "amazon", "אמזון", "aliexpress",
            "shein", "asos", "ksp", "אייס", "ace", "הום סנטר", "home center", "מקס סטוק", "max stock",
            "nike", "adidas", "next", "mango", "bershka", "pull bear", "decathlon", "דקטלון", "h m", "pullbear",
            "ליידי קומפורט", "גולף", "golf", "אופיס דיפו", "office depot", "באג", "איביי", "ebay", "temu",
        ]),
        (.kids, [
            "שילב", "shilav", "טויס אר אס", "toys r us", "toysrus", "צעצועים", "toys", "גן ילדים", "צהרון",
        ]),
        (.pets, [
            "פט שופ", "pet shop", "petshop", "חיות מחמד", "pets", "וטרינר", "veterinary", "vet", "zoo",
        ]),
        (.education, [
            "סטימצקי", "steimatzky", "צומת ספרים", "tzomet sfarim", "אוניברסיטת", "university", "מכללת",
            "college", "udemy", "coursera", "ספרים", "books",
        ]),
        (.gifts, [
            "פרחים", "flowers", "פרח", "זר פרחים",
        ]),
        (.housing, [
            "ועד בית", "שכירות", "rent",
        ]),
    ]
}
