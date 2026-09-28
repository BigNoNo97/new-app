// The Hebrew alert partners get when someone in the household logs a transaction.

export interface PartnerActivity {
  authorName: string;
  kind: "expense" | "income";
  merchant: string | null;
  categoryName: string | null;
  categoryEmoji: string | null;
  amount: number;
  currency: string;
}

export interface Alert {
  title: string;
  body: string;
}

const SYMBOLS: Record<string, string> = {
  ILS: "₪", USD: "$", EUR: "€", GBP: "£", JPY: "¥", RUB: "₽", THB: "฿", UAH: "₴", TRY: "₺", INR: "₹",
};

// "₪212.40", "$12", wrapped in a left-to-right isolate so it reads right inside Hebrew text.
export function formatAmount(amount: number, currency: string): string {
  const hasCents = Math.round(amount * 100) % 100 !== 0;
  const number = Math.abs(amount).toLocaleString("en-US", {
    minimumFractionDigits: hasCents ? 2 : 0,
    maximumFractionDigits: 2,
  });
  const symbol = SYMBOLS[currency] ?? `${currency} `;
  return `⁦${amount < 0 ? "-" : ""}${symbol}${number}⁩`;
}

// First name only, as on the home screen.
export function firstName(fullName: string): string {
  const trimmed = fullName.trim();
  return trimmed.split(/\s+/)[0] ?? trimmed;
}

// Title: "הוצאה חדשה ממיכל" (gender-neutral, unlike "מיכל הוסיפה").
// Body: "🛒 רמי לוי · ₪212.40".
export function partnerAlert(activity: PartnerActivity): Alert {
  const name = firstName(activity.authorName) || "השותף";
  const noun = activity.kind === "income" ? "הכנסה חדשה" : "הוצאה חדשה";
  const what = activity.merchant?.trim() || activity.categoryName?.trim() || (activity.kind === "income" ? "הכנסה" : "הוצאה");
  const emoji = activity.categoryEmoji ? `${activity.categoryEmoji} ` : "";
  return {
    title: `${noun} מ${name}`,
    body: `${emoji}${what} · ${formatAmount(activity.amount, activity.currency)}`,
  };
}
