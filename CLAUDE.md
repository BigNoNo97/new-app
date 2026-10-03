# CLAUDE.md

## אופן עבודה

- כשצעד לא דורש קלט ממני — תמשיך לצעד הבא בלי לעצור. כתוב עדכון סטטוס קצר באותה הודעה יחד עם הפעולה הבאה, לא בהודעה נפרדת.
- תעצור ותשאל רק כש:
  - אתה לא יכול להמשיך בלעדיי (חסר מידע, הרשאה או החלטה שרק אני יכול לקבל).
  - לפני כל פעולה הרסנית: מחיקת נתונים, force-push, או שינוי של כל דבר מחוץ לריפו הזה.

## מעקב משימות

- נהל צ'קליסט בקובץ `TASKS.md` בשורש הריפו.
- סמן כל פריט (`- [x]`) ברגע שהוא גמור.
- כל דבר חדש שאתה מוצא תוך כדי עבודה (באג, משימת המשך, חוב טכני) — הוסף כפריט חדש (`- [ ]`).

## שפה ועיצוב תשובות

- כל תשובה למשתמש — בעברית בלבד.
- עיצוב שתומך ב-RTL:
  - כל שורה ופריט ברשימה מתחילים במילה בעברית, לא במונח באנגלית, בקוד או במספר.
  - מונחים באנגלית, שמות קבצים ופקודות — בתוך `backticks`, באמצע משפט.
  - בלי טבלאות; רשימות ותבליטים במקומן.
  - קוד ופקודות ארוכים — בבלוק קוד נפרד, לא בתוך משפט עברי.

## הפרויקט: SnaPay

אפליקציית iOS למעקב הוצאות והכנסות, בעברית. התוכנית המלאה נמצאת ב-`docs/PLAN.md`, וההתקדמות ב-`TASKS.md`.

### מבנה

- `project.yml` — הגדרת פרויקט Xcode. הקובץ `SnaPay.xcodeproj` נוצר ממנו עם XcodeGen, ולא נשמר בגיט.
- `SnaPay/` — קוד האפליקציה, ב-SwiftUI, ל-iOS 26 ומעלה.
- `SnaPay/DesignSystem/` — צבעים, מרווחים ורכיבי זכוכית. כל צבע באפליקציה מגיע מ-`Theme`.
- `SnaPayWidget/` — הווידג'ט.
- `Packages/SnaPayCore/` — לוגיקה עסקית בלי ממשק: המרת מטבע, חודש פיננסי, חיובים מחזוריים, הצעת קטגוריה וקריאת קבצי עו"ש. כל לוגיקה שאפשר לבדוק בלי ממשק נכנסת לכאן, עם טסטים.
- `SnaPay/App/AppState.swift` — מצב האפליקציה: איזה מסך מוצג וזרימות החשבון. השירותים (`SnaPay/Core/Services/`) מוגדרים כפרוטוקולים, עם מימוש Firebase (`FirebaseServices.swift`) ומימוש בזיכרון לטסטי ממשק (`-uiTesting`).
- `SnaPay/Features/QuickLog/` — תיעוד בקליק: פעולת קיצורים (`LogPaymentIntent`) שמתחילה Live Activity, מסך הדרכה וכרטיסי מסך הבית. נתוני ה-Live Activity והפעולות של הכפתורים שלו ב-`Shared/QuickLogActivity.swift` (משותף לאפליקציה ולווידג'ט), והתצוגה ב-`SnaPayWidget/QuickLogActivityWidget.swift`. הפעולה שומרת תשלומים לתיבת קליטה משותפת ב-App Group (`SnaPay/Core/QuickLog/QuickLogStorage.swift`), והמחסן הופך אותם לתנועות.
- `SnaPay/Features/Settings/` — מסך ההגדרות והחשבון המשותף. משתמש שייך למשק בית אחד. הצטרפות, יציאה והסרה רצות באפליקציה עצמה (`FirebaseServices`), כי בחבילה החינמית של Firebase אין פונקציות שרת, וההוצאות של המשתמש עוברות איתו. שותף שהוסר מסומן `removed`, והאפליקציה שלו מעבירה את הנתונים שלו בפתיחה הבאה.
- `SnaPay/Core/Services/PushNotifications.swift` — רישום להתראות. הטוקנים נשמרים ב-Firestore, אבל עוד אין שרת ששולח לשותפים התראה על תנועה חדשה (ראו `TASKS.md`).
- טסטי ממשק עם שותפה מדומה: `invited@example.com` מקבל הזמנה, ו-`shared@example.com` כבר בחשבון משותף.
- `SnaPay/Core/Store/TransactionStore.swift` — נתוני משק הבית באפליקציה: עותק מקומי בקובץ ב-App Group, תור שינויים (outbox) לעבודה בלי רשת, ויצירת חיובים קבועים בכל פתיחה.
- `SnaPayUITests/` — טסטי ממשק. בכל ריצה ב-CI נשמרים צילומי מסך בבהיר ובכהה כקובץ `screenshots` של הבנייה.
- `firebase/` — צד השרת ב-Firebase (חבילה חינמית: Auth ו-Firestore): חוקי האבטחה (`firestore.rules`), אינדקסים, וטסטים לחוקים מול האמולטור (`tests/`). מבנה המסמכים מתואר בראש קובץ החוקים, והמסמכים הם ה-JSON של המודלים (`FirestoreJSON` ב-SnaPayCore).
- צילומי המסך האחרונים מה-CI נמצאים גם בענף `ci-screenshots`. אפשר למשוך אותם עם `git fetch origin ci-screenshots` ולפתוח את הקבצים לבדיקה ויזואלית.
- `Config/App.xcconfig` — הגדרות Firebase (ארבעה ערכים ציבוריים מ-`GoogleService-Info.plist`). הצינור כותב את `Config/Secrets.xcconfig` ממשתני הריפו.
- `signing/` — פרופילי App Store לחתימה ידנית ב-`testflight.yml`. התעודה והמפתח נמצאים רק בסודות של GitHub.
- `site/` — דפי מדיניות הפרטיות ותנאי השימוש (סטטיים, בעברית). ‏`pages.yml` מפרסם אותם ל-`https://bignono97.github.io/new-app/` בכל מיזוג ל-`main`. האפליקציה (`AppConfig.privacyURL`) ו-TestFlight מקשרים אליהם.
- `docs/design/claude-design-prompt.md` — הפרומפט ל-Claude Design.
- `docs/design/claude-design/` — העיצוב מ-Claude Design, והוא מקור האמת לכל מסך. בתיקייה:
  - `screens/<id>-light.jpg` ו-`screens/<id>-dark.jpg`: צילום של כל מסך בבהיר ובכהה.
  - `source/<id>-light.dc.html`: המידות המדויקות. כשהצילום והמקור לא מסכימים, סומכים על המקור.
  - `design-tokens/tokens.json`: כל הטוקנים.
  - `brand/`: האייקון והלוגו.
  - `README.md`: חוקי העיצוב והזרימות.
- `.github/workflows/` — בדיקת קוד על כל שינוי, והעלאה ל-TestFlight על כל מיזוג ל-`main`.

### בנייה ובדיקה

אין Mac בסביבת הפיתוח, ובסביבת הענן אין Swift. הקמפול והטסטים רצים ב-GitHub Actions על macOS. פקודות מקבילות על Mac:

בסביבת הענן אפשר להריץ את טסטי חוקי האבטחה של Firestore מול האמולטור (צריך Node ו-Java):

```
cd firebase && npm ci && npm test
```

פקודות לבדיקת האפליקציה על Mac:

```
swift test --package-path Packages/SnaPayCore
brew install xcodegen && xcodegen generate
xcodebuild test -project SnaPay.xcodeproj -scheme SnaPay -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

- **דקות Actions:** מ-1.10 הריפו ציבורי, ולכן הדקות חינמיות (גם על macOS), אחרי שהמכסה של הריפו הפרטי נגמרה. הוא גלוי לכולם: אסור להכניס לריפו סודות, מפתחות או קבצי `GoogleService-Info.plist`. הכללים כאן נשארים בשביל המהירות:
  - טסטי `SnaPayCore` רצים על לינוקס בכל שינוי.
  - הבנייה על macOS, טסטי הממשק וצילומי המסך רצים רק ב-PR שאינו טיוטה, או בהפעלה ידנית.
  - אופן העבודה: פותחים PR כטיוטה, בודקים מקומית ככל האפשר, ומעבירים ל-"Ready for review" רק בסוף שלב. תיקונים אחרי זה נאספים לדחיפה אחת.
- כל שינוי במבנה הנתונים או בהרשאות עובר ב-`firebase/firestore.rules`, עם טסט מתאים ב-`firebase/tests/`. שאילתה חדשה עם מיון וסינון צריכה אינדקס ב-`firebase/firestore.indexes.json`.
- כתיבות לשרת נעשות באצוות קטנות (`FirebaseServices.batchSize`), כי חוקי האבטחה קוראים עד שני מסמכים לכל כתיבה, ויש מגבלה לכל בקשה.

### כללי עיצוב (חובה)

- בלי רקע בצבע שמנת, בלי טקסט באיטליק, בלי תוויות ממוספרות כמו "01", בלי פונט מונוספייס.
- בלי כפתורים או פקדים בצורת גלולה: רק מלבנים עם פינות מעוגלות (`Radius.control`). הכפתור העגול היחיד הוא "+" בבר הניווט.
- כל המסכים מימין לשמאל.
