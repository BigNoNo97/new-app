# SnaPay – design handoff for implementation (SwiftUI, iOS 26)

This folder is the complete design for SnaPay, a personal and family expense and income tracker for the Israeli market. The UI is Hebrew and fully right-to-left, and every screen exists in light and dark mode. Implement it 1:1 in SwiftUI.

## What's in here

| Path | What it is | How to use it |
|---|---|---|
| `screens/*.jpg` | A rendered image of every screen, light and dark (`home-light.jpg`, `home-dark.jpg` …) | Look at these first. They are the visual target. |
| `screens/index.json` | List of all screens: flow, title, id, size | Map of what exists. |
| `source/*.dc.html` | The HTML/CSS source of each screen | The exact numbers: padding, font sizes, colors, radii, copy. When an image and the source disagree, trust the source. |
| `source/Main.dc.html`, `components-*.dc.html`, `logo.dc.html` | Tokens sheet, component sheet, logo and icon sheet | Reference for the design system. |
| `design-tokens/tokens.json` | All tokens: colors (light/dark), category colors, type scale, spacing, radius, glass, sizes, motion | Single source of truth for values. |
| `swift/SnaPayTheme.swift` | Colors, fonts, spacing, radius, glass modifier, amount view, primary button style | Drop into the project and build on it. |
| `swift/SnaPayColors.xcassets` | Every color token as a color set with Any and Dark appearances, plus the 16 category colors | Drag into Xcode. Names match `Color.<token>` in the Swift file. |
| `brand/` | Logo symbol (color, on-dark, mono) and app icon SVGs, plus 1024px PNGs (light, dark, tinted) | App icon and in-app logo. |

Screen renders are approximate: they were rendered in a browser with a fallback font, so text is slightly wider than it will be with SF Pro / SF Hebrew on the device. Use the source for exact sizes.

## Suggested order of work

1. Import `SnaPayColors.xcassets` and `SnaPayTheme.swift`, set the app icon from `brand/`.
2. Build the shared components from `source/components-light.dc.html`: buttons, text fields, checkbox, switch, segmented control, category tile, transaction row, glass card, progress ring, progress bar, bottom sheet, floating tab bar, filter chip, empty states.
3. Build the screens flow by flow (list below), checking each against its light and dark images.

## Hard rules (the design depends on these)

- No capsule shapes anywhere: buttons, chips, segmented controls, switches and the tab bar are rounded rectangles, radius 12–16 (tab bar 22, cards 24, sheets 32). Never use `.capsule` or `Capsule()`. Full circles are only for avatars and the centre "+" button.
- The switch is custom: 52×32, radius 11, square-ish knob radius 9. Do not use the system `Toggle` style.
- No italics, no monospaced fonts. Amounts use SF Pro semibold with `.monospacedDigit()`.
- No cream or beige backgrounds. No numbered step labels ("01", "1/5"); progress is shown as a line.
- Fully RTL: `.environment(\.layoutDirection, .rightToLeft)` app-wide. Amounts are LTR-isolated so the currency sign stays before the number: `₪3,453`, `€42.00`, `+₪14,200`.
- Tab bar order, right to left: בית · הוצאות · [+] · יעדים · פרופיל. The "+" is a 62pt green circle raised 30pt above the bar and opens the Add sheet.
- Backgrounds: light is a cool white to pale mint gradient with soft blooms; dark is near-black navy to deep teal with blurred bokeh. Content sits on glass cards (`.glassEffect`, radius 24, 1pt top highlight).
- Category icons are emoji inside a tinted rounded tile (tint 16% light / 22% dark of the category color). All other icons are SF Symbols, rounded, medium weight.

## Flows and screens

Ids are file names without `-light`/`-dark`.

**Onboarding** – `faceid` (Face ID lock) · `notif` (notification pre-prompt) · `welcome` · `signup` / `signuperr` (passwords don't match) · `login` · `forgot` / `forgotok` (reset sheet and success) · `hello` (nice to meet you) · `categories` / `editcat` (pick categories, edit-category sheet) · `setup` / `setupwait` (Apple Pay Shortcuts automation guide and waiting state).

**Quick-log (signature moment)** – `quicklog` · `quicklogsaved` · `quicklogfx`. After an Apple Pay payment a black card expands out of the Dynamic Island (Live Activity style): merchant, amount, card, 4 suggested categories (most likely first, highlighted) and "עוד…". Tapping a category saves; the card collapses to a compact island "נשמר באוכל ומסעדות" with undo. The foreign-currency variant shows `$23.00 ≈ ₪86.40 כולל עמלה`.

**Home** – `home` (full scroll capture, 1640pt) · `homeempty`. Greeting and avatar, shared-account indicator, period switcher (השבוע / החודש / אחר), hero total with comparison chip and income/expense bar, pending items needing a category (highlighted, at the top), budget alerts row, active-trip card, feed grouped by day. Each row shows the category tile, merchant, who logged it (avatar), amount and a source icon (Apple Pay / manual / receipt / recurring / import).

**Expenses** – `expenses` · `expmenu` (top-bar menu: ייבוא מעו״ש, ייצוא לקובץ) · `expempty` · `filter` (filter sheet) · `detail` (expense detail with original currency, rate and fee breakdown; delete only for your own entries) · import flow `import1` (pick file) → `import2` (column mapping with preview) → `import3` (review and assign categories, duplicates skipped) → `import4` (done).

**Add** – `add` (amount entry with custom number pad; currency defaults to the active trip's; live conversion including the card's FX fee) · `adddetails` (details, "צלם קבלה", recurring charge: weekly / monthly / yearly / custom, start date, optional end date).

**Goals** – `goals` (1000pt) · `goalsempty` · `goal` (detail with deposit history, deposit and withdraw) · `newgoal` (create-goal sheet with optional monthly auto-deposit). Rings go green to lime.

**Profile and settings** – `profile` (full scroll, 2080pt: balance, 6-month bar chart with the current month in green, category breakdown, stats, budgets, past recaps, "hide housing" toggle; the gear on the top card opens settings) · `settings` (full scroll, 2900pt) · `deleteacct` (confirmation requires typing "מחק").

**Monthly recap** – `recap1` … `recap7`: stories with a thin segmented progress line; total, top category, top merchant, biggest expense, vs last month, savings, and the closing card "זה היה ספטמבר שלך." with share.

**Widgets** – `widgets`: small and medium home-screen widgets (month spend, budget bar, quick-add "+").

## Motion

- Card press: scale 1.01, lift 2pt, `spring(response: 0.3, dampingFraction: 0.7)`.
- Quick-log: morphs out of the Dynamic Island, `spring(response: 0.45, dampingFraction: 0.72)`; saved state auto-dismisses after 2.5s.
- Amounts count up (0.6s, `.contentTransition(.numericText())`); rings and bars fill over 0.8s on appear.
- Recap: 5s per card, tap right half to go back and left half to go forward; glass blocks stack with a staggered spring.

## Logo

The symbol is a receipt whose lines have become rising bars, topped by a lime coin with a check. Wordmark: "SnaPay" in Rubik Bold, with "Pay" in brand green (#16804A light, #3DDC84 dark). Optional tagline "הוצאות בלחיצה" in Heebo Medium, wide tracking. For iOS 26 icon variants, rebuild it in Icon Composer with three layers (background, receipt and bars, coin) so the system can generate Clear and Tinted.

## Sample data

Names, merchants and amounts in the screens are illustrative (for example ₪3,453 this month, ₪211 below August), but they are consistent with each other, so they can be reused as preview and test data.
