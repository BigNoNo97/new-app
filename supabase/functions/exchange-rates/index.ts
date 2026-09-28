// Returns the latest reference exchange rates, expressed as the value of one unit of each
// currency in ILS. Rates are fetched at most once a day (Bank of Israel, with Frankfurter/ECB
// filling in currencies the Bank doesn't publish) and stored in public.exchange_rates, so no
// scheduled job is needed: the first request of the day refreshes them.
//
// GET /functions/v1/exchange-rates  (signed-in users)
// → {"base":"ILS","date":"2026-09-28","rates":{"USD":3.7,...}}

import { createClient } from "npm:@supabase/supabase-js@2";
import { mergeRates, parseBankOfIsrael, parseFrankfurter, type RatesResult } from "./parse.ts";

const BOI_URL = "https://boi.org.il/PublicApi/GetExchangeRates";
const FRANKFURTER_URL = "https://api.frankfurter.app/latest?from=ILS";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "max-age=3600" },
  });
}

async function fetchJSON(url: string): Promise<unknown> {
  try {
    const response = await fetch(url, { headers: { Accept: "application/json" }, signal: AbortSignal.timeout(8000) });
    return response.ok ? await response.json() : null;
  } catch (error) {
    console.error("exchange-rates: fetch failed", url, error);
    return null;
  }
}

function todayInIsrael(): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jerusalem" }).format(new Date());
}

Deno.serve(async (req) => {
  if (req.method !== "GET" && req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return json({ error: "server_misconfigured" }, 500);
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  // Latest stored rates.
  const { data: latestRow } = await admin
    .from("exchange_rates")
    .select("rate_date, fetched_at")
    .eq("base", "ILS")
    .order("rate_date", { ascending: false })
    .order("fetched_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  const fetchedToday = latestRow?.fetched_at && String(latestRow.fetched_at).slice(0, 10) >= todayInIsrael();

  if (!fetchedToday) {
    const fresh: RatesResult | null = mergeRates(
      parseBankOfIsrael(await fetchJSON(BOI_URL)),
      parseFrankfurter(await fetchJSON(FRANKFURTER_URL)),
    );
    if (fresh) {
      const rows = Object.entries(fresh.rates).map(([quote, rate]) => ({
        base: "ILS",
        quote,
        rate,
        rate_date: fresh.date,
        source: fresh.source,
        fetched_at: new Date().toISOString(),
      }));
      const { error } = await admin.from("exchange_rates").upsert(rows, { onConflict: "base,quote,rate_date" });
      if (error) console.error("exchange-rates: store failed", error);
    }
  }

  // Newest rate per currency.
  const { data, error } = await admin
    .from("exchange_rates")
    .select("quote, rate, rate_date")
    .eq("base", "ILS")
    .order("rate_date", { ascending: false })
    .limit(2000);
  if (error || !data || data.length === 0) {
    return json({ error: "rates_unavailable" }, 503);
  }
  const rates: Record<string, number> = {};
  let date = "";
  for (const row of data) {
    if (rates[row.quote] === undefined) rates[row.quote] = Number(row.rate);
    if (row.rate_date > date) date = row.rate_date;
  }
  return json({ base: "ILS", date, rates });
});
