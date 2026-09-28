// Pure parsing for the exchange-rates function, kept separate so it can be unit-tested
// without network or database access.

/** Value of one unit of each currency in ILS. */
export type RatesToILS = Record<string, number>;

export interface RatesResult {
  base: "ILS";
  /** yyyy-MM-dd */
  date: string;
  rates: RatesToILS;
  source: string;
}

const CODE = /^[A-Z]{3}$/;

function round8(value: number): number {
  return Math.round(value * 1e8) / 1e8;
}

/**
 * Bank of Israel representative rates:
 * {"exchangeRates":[{"key":"USD","currentExchangeRate":3.7,"unit":1,"lastUpdate":"2026-09-28T12:00:00Z"}]}
 * `unit` is how many units the rate is quoted for (JPY is per 100); it may be missing.
 */
export function parseBankOfIsrael(body: unknown): RatesResult | null {
  const list = (body as { exchangeRates?: unknown })?.exchangeRates;
  if (!Array.isArray(list)) return null;
  const rates: RatesToILS = {};
  let latest = "";
  for (const entry of list) {
    const key = String(entry?.key ?? "").toUpperCase();
    const rate = Number(entry?.currentExchangeRate);
    const unit = Number(entry?.unit ?? 1) || 1;
    if (!CODE.test(key) || !Number.isFinite(rate) || rate <= 0) continue;
    rates[key] = round8(rate / unit);
    const updated = String(entry?.lastUpdate ?? "").slice(0, 10);
    if (updated > latest) latest = updated;
  }
  if (Object.keys(rates).length === 0) return null;
  return { base: "ILS", date: latest || new Date().toISOString().slice(0, 10), rates, source: "bank-of-israel" };
}

/**
 * Frankfurter (ECB) rates from ILS: {"base":"ILS","date":"2026-09-25","rates":{"USD":0.27}}
 * means 1 ILS = 0.27 USD, so 1 USD = 1 / 0.27 ILS.
 */
export function parseFrankfurter(body: unknown): RatesResult | null {
  const data = body as { base?: string; date?: string; rates?: Record<string, unknown> };
  if (data?.base !== "ILS" || typeof data.rates !== "object" || data.rates === null) return null;
  const rates: RatesToILS = {};
  for (const [code, value] of Object.entries(data.rates)) {
    const perILS = Number(value);
    if (!CODE.test(code) || !Number.isFinite(perILS) || perILS <= 0) continue;
    rates[code] = round8(1 / perILS);
  }
  if (Object.keys(rates).length === 0) return null;
  return { base: "ILS", date: String(data.date ?? "").slice(0, 10), rates, source: "frankfurter" };
}

/** Merges fallback rates under primary ones (primary wins), so rare currencies are still covered. */
export function mergeRates(primary: RatesResult | null, fallback: RatesResult | null): RatesResult | null {
  if (!primary) return fallback;
  if (!fallback) return primary;
  return { ...primary, rates: { ...fallback.rates, ...primary.rates } };
}
