# Claude Design prompt: SnaPay

Paste everything below the line into Claude Design.

---

Design a complete, high-fidelity iOS 26 app called **SnaPay** — a personal and family expense & income tracker for the Israeli market. The interface is in **Hebrew, fully right-to-left**. Produce every screen listed below in **both light and dark mode**, at iPhone 16 Pro size (393×852 pt).

## What the app does

SnaPay makes logging spending effortless. Its signature moment: right after the user pays with Apple Pay, a small glass card pops up showing the amount and merchant, with 3–4 suggested categories. One tap and the expense is logged. Around that core: income and recurring charges, multi-currency with a travel mode, shared family accounts, savings goals, category budgets, a monthly recap, a home-screen widget, and receipt scanning.

## Visual language: clean, modern Liquid Glass

Take direction from Apple's iOS 26 Liquid Glass and from this reference mood: frosted translucent cards floating over a deep, atmospheric background, soft specular edges, generous blur, calm and premium.

- **Dark mode background:** a deep, abstract gradient (near-black navy to deep teal) with soft, blurred bokeh light spots, like city lights at night seen through glass. No photos of people.
- **Light mode background:** cool white to very pale blue-mint gradient with faint soft color blooms. Crisp, airy.
- **Glass surfaces:** translucent cards with background blur, a 1pt inner highlight on the top edge, subtle shadow, corner radius 24pt for cards and 16pt for controls.
- **Brand color:** a fresh green (around #2FB36D in light, #3DDC84-ish in dark; tune for contrast). Use it for primary actions, positive balances, and progress.
- **Secondary accents:** a lime/chartreuse (for "savings") and one category color per category, used sparingly as small tints and bar fills.
- **Negative/expense emphasis:** a soft coral red, never alarming.
- **Typography:** SF Pro / SF Hebrew (system font). Large confident numbers for amounts (weight semibold), clear hierarchy, regular weight for body. Currency symbol placed per Hebrew convention (₪1,653).
- **Icons:** SF Symbols, rounded, medium weight. Categories use emoji inside a soft tinted glass tile.
- **Motion notes (annotate):** cards lift slightly on press; the quick-log card springs up from the bottom; numbers count up.

## Hard rules: do NOT use any of these

1. No cream, beige, or off-white "paper" backgrounds.
2. No bold-italic text, and no italic emphasis at all.
3. No numbered labels or step counters like "01", "02", "03" or "1/5".
4. No monospace fonts anywhere, including numbers.
5. No pill-shaped (fully rounded / capsule) buttons, chips, segmented controls or tab bars. Every button and control is a rounded rectangle (corner radius 12–16pt), never a capsule. This includes the period switcher and the bottom navigation.

## Navigation

A floating glass bottom bar (rounded rectangle, not a capsule) with five items, ordered right-to-left:
**בית** · **הוצאות** · **[+]** · **יעדים** · **פרופיל**.
The center "+" is a prominent circular green glass button, slightly raised above the bar. It's the only circle in the bar.

## Screens

### 1. Notification permission (first launch)
Friendly pre-prompt before the system dialog: an illustration of a glass card with a notification bell, title "נשאר מעודכנים", text "נעדכן אותך כשבן משפחה מוסיף הוצאה, כשמתקרבים לתקציב, וכשהסיכום החודשי מוכן." Buttons: "אפשר התראות" (primary) and "אולי אחר כך" (text button).

### 2. Welcome
Full-bleed atmospheric background, a hero composition of floating glass cards (an expense card, a category tile, a small chart) that tells the story at a glance. Title: "כל הוצאה, בלחיצה אחת." Subtitle: "SnaPay קולט את התשלום מהאייפון, ואתה רק בוחר קטגוריה." Three short feature highlights with icons (no numbers): תיעוד אוטומטי מ-Apple Pay · ניהול משותף למשפחה · יעדים ותקציבים.
Two stacked buttons: "בוא נתחיל" (primary, green) → sign-up; "יש לי כבר חשבון" (secondary glass) → log-in.

### 3. Sign up
Glass form card. Fields: שם מלא, אימייל, סיסמה, אימות סיסמה. Both password fields have an eye icon to show/hide. Below: main currency picker "המטבע העיקרי שלי" (default ₪ שקל). Checkbox: "קראתי ואני מאשר/ת את תנאי השימוש ומדיניות הפרטיות" (the two terms are links). Primary button "הרשמה". Footer: "כבר יש לך חשבון? להתחברות". Show an error state (passwords don't match) as a second frame.

### 4. Log in
Glass form card. Fields: אימייל, סיסמה (with eye icon). Under the password: "שכחת סיסמה?" link. Checkbox for terms. Primary button "התחברות". Footer: "אין לך חשבון עדיין? לחץ להרשמה".
Also design the **forgot-password sheet**: email field, "שלחו לי קישור לאיפוס", and a success state "שלחנו לך מייל".

### 5. Nice to meet you
Big warm title "[שם פרטי], נעים להכיר!" A short paragraph on what SnaPay does, then a vertical list of feature cards (icon + title + one line): תיעוד בקליק מ-Apple Pay · הכנסות וחיובים קבועים · חשבון משותף למשפחה · מטבעות ונסיעות לחו"ל · יעדי חיסכון ותקציבים · סיכום חודשי. Primary button "נתחיל!".

### 6. Choose your categories
Title "איך אתה מוציא כסף?" Subtitle "בחרנו בשבילך את הבסיס. אפשר לשנות, להוסיף ולעצב." A grid of category tiles (emoji in tinted glass + name), selected state has a green border and check:
🍔 אוכל ומסעדות · 🛒 סופר · 🛍️ קניות · 🚗 רכב ודלק · 🚌 תחבורה ציבורית · 🏠 דיור · 💡 חשבונות · 📱 תקשורת · 💊 בריאות · 🎬 בילויים · ✈️ טיולים · 🎁 מתנות · 👶 ילדים · 🐾 חיות מחמד · 📚 לימודים · ☕ קפה.
A "+ קטגוריה חדשה" tile. Also design the **edit-category sheet**: name field, emoji picker grid, color swatches, expense/income toggle.

### 7. Set up tap-to-log (Apple Pay automation guide)
A guided screen with a progress bar at the top (a line, not numbered steps). Illustrated instructions for creating a Shortcuts "Transaction" automation, a button "פתח את קיצורים", then the waiting state: title "ההגדרה הסתיימה", text "מחכה לקליטה הראשונה מהפעולה האוטומטית. אחרי התשלום הבא נדע שהכול מחובר.", an animated illustration (card → phone → SnaPay), and "סיימתי" button. Include a "דלג בינתיים" text link.

### 8. Quick-log card (the signature moment)
A compact glass card as it appears over the lock/home screen after an Apple Pay payment: merchant name and logo placeholder, amount large ("₪48.90"), card name small, then a row of 4 suggested category tiles (most likely first, highlighted), and a small "עוד…" option. Show: default state, selected/saved state with a green check ("נשמר באוכל ומסעדות"), and a foreign-currency variant ("$23.00 ≈ ₪86.40 כולל עמלה").

### 9. Home (בית)
- Top: greeting and avatar; a shared-account indicator when active (small stacked avatars).
- Period switcher: "השבוע" / "החודש" / "אחר" — a rounded-rectangle segmented control (not capsule).
- Hero glass card: total spent this period ("₪3,453"), comparison chip ("↓ ₪211 פחות מהחודש שעבר"), income vs. expenses mini-bar.
- Budget alerts row: small cards for categories near their limit (progress bar, "85% מהתקציב").
- If a trip is active: a travel card ("טיול לאיטליה · €" with spent-in-euro and in-shekel).
- Feed: all expenses newest-first, grouped by day ("היום", "אתמול", "יום ג׳, 23 בספט׳"). Each row: category emoji tile, merchant/description, who logged it (avatar, in shared mode), amount, small source icon (Apple Pay / manual / receipt).
- Pending items needing a category appear at top with a subtle highlight.

### 10. Expenses (הוצאות)
Full list with a search bar and filter chips (rounded rectangles): קטגוריה, תאריך, סכום, בן משפחה, מטבע, מקור, הוצאה/הכנסה. A filter sheet design. Top-bar menu with "ייבוא מעו״ש" and "ייצוא לקובץ". Design the **import flow**: pick file → column-mapping screen (תאריך, תיאור, סכום) with preview rows → review & assign categories → done.
Also an **expense detail** screen: amount, original currency + rate + fee breakdown, category, date, note, receipt photo thumbnail, who logged it, edit/delete (delete only for own entries).

### 11. Add (+) sheet
A large glass bottom sheet. Toggle at top: "הוצאה" / "הכנסה". Big amount entry with custom number pad, currency selector next to the amount (defaults to active trip currency), live conversion line ("≈ ₪86.40 כולל 2.5% עמלת המרה"). Category row (horizontal scroll of tiles), merchant/description field, date, note, "צלם קבלה" button (camera → auto-fills amount and merchant), and a "חיוב קבוע" switch that reveals: frequency (שבועי / חודשי / שנתי / מותאם), start date, end date (optional). Primary "שמירה".

### 12. Goals (יעדים)
Interactive and delightful. Grid of goal cards, each with an emoji, name, big progress ring (green→lime), "₪4,200 מתוך ₪10,000", target date and "₪350 בחודש כדי להגיע בזמן". Goal detail: ring, deposit history, "הפקדה" and "משיכה" buttons. Create-goal sheet: name, emoji, target amount, target date, optional monthly auto-deposit.

### 13. Profile (פרופיל)
Top glass card: full name, small "הצטרף בספטמבר 2026", and a gear icon on the same card that opens settings.
Below: insights and reports —
- Balance card: income vs. expenses this month, net savings.
- Monthly comparison bar chart (last 6 months), current month highlighted in green.
- Category breakdown: horizontal bars with percentages (like: אוכל ומסעדות ₪987 · 60%).
- Stats row: ממוצע ליום, מספר עסקאות, הוצאה שיא.
- Budgets overview.
- Past monthly recaps list.
- A toggle "הסתר הוצאות דיור מהחישוב".

### 14. Settings (הגדרות)
Grouped glass list:
- **הפרופיל שלי:** שם תצוגה, אימייל, שינוי סיסמה.
- **חשבון משותף:** on/off switch, partners list (name + email + status: פעיל / הוזמן), "הזמנת שותף" (email field). Note text: "כל שותף מתעד רק את ההוצאות שלו, ורואה את של כולם."
- **תחילת החודש:** ה-1 לחודש / ה-10 לחודש / תאריך אחר.
- **מטבע ועמלות:** מטבע עיקרי, עמלת המרה של כרטיס האשראי (%).
- **טיולים:** list + "טיול חדש" (name, destination currency, dates).
- **תקציבים:** per category.
- **Face ID:** switch.
- **תיעוד בקליק:** switch + "הגדר מחדש את האוטומציה".
- **התראות:** switches per type.
- **התנתקות** (neutral) and **מחיקת החשבון שלי** (destructive red) with a confirmation dialog: "הפעולה תמחק לצמיתות את החשבון וכל המידע שהזנת. אי אפשר לשחזר." requiring typing "מחק".

### 15. Monthly recap (stories)
5–6 full-screen story cards with a thin segmented progress line at the top (no numbers). Each card is a bold, playful composition with a large number and a simple geometric illustration (towers/bars made of glass blocks, not a city game): total spent, top category, top merchant, biggest single expense, vs. last month, savings progress. Final card: "זה היה ספטמבר שלך." with a share button.

### 16. Home-screen widget
Small and medium sizes, light and dark: this month's spend, budget progress bar, and a "+" quick-add button.

### 17. Face ID lock screen
Minimal glass screen with the app mark and "פתח עם Face ID".

## Components to deliver as a system
Buttons (primary, secondary glass, text, destructive) — all rounded rectangles. Text fields (default, focused, error, with eye icon). Checkbox. Switch. Segmented control (rounded rectangle). Category tile. Transaction row. Glass card. Progress ring. Progress bar. Bottom sheet. Bottom navigation bar. Filter chip (rounded rectangle). Empty states for Home, Expenses and Goals.

## Output
All screens in light and dark mode, the component sheet, the color tokens (light/dark), the type scale, and spacing/radius tokens, so the design can be implemented 1:1 in SwiftUI.
