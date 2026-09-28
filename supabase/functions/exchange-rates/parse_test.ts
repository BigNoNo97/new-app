import { assertEquals } from "jsr:@std/assert@1";
import { mergeRates, parseBankOfIsrael, parseFrankfurter } from "./parse.ts";

Deno.test("parses Bank of Israel rates, dividing by unit", () => {
  const result = parseBankOfIsrael({
    exchangeRates: [
      { key: "USD", currentExchangeRate: 3.7, currentChange: -0.1, lastUpdate: "2026-09-28T12:00:00Z" },
      { key: "JPY", currentExchangeRate: 2.46, unit: 100, lastUpdate: "2026-09-27T12:00:00Z" },
      { key: "BAD", currentExchangeRate: -1 },
      { key: "toolong", currentExchangeRate: 1 },
    ],
  });
  assertEquals(result, {
    base: "ILS",
    date: "2026-09-28",
    rates: { USD: 3.7, JPY: 0.0246 },
    source: "bank-of-israel",
  });
});

Deno.test("rejects unexpected Bank of Israel payloads", () => {
  assertEquals(parseBankOfIsrael({}), null);
  assertEquals(parseBankOfIsrael({ exchangeRates: [] }), null);
  assertEquals(parseBankOfIsrael(null), null);
});

Deno.test("inverts Frankfurter rates to value in ILS", () => {
  const result = parseFrankfurter({ amount: 1, base: "ILS", date: "2026-09-25", rates: { USD: 0.25, EUR: 0.2 } });
  assertEquals(result?.rates, { USD: 4, EUR: 5 });
  assertEquals(result?.date, "2026-09-25");
  assertEquals(parseFrankfurter({ base: "USD", rates: { ILS: 3.7 } }), null);
});

Deno.test("primary rates win when merging", () => {
  const primary = parseBankOfIsrael({ exchangeRates: [{ key: "USD", currentExchangeRate: 3.7, lastUpdate: "2026-09-28" }] });
  const fallback = parseFrankfurter({ base: "ILS", date: "2026-09-25", rates: { USD: 0.25, THB: 10 } });
  assertEquals(mergeRates(primary, fallback)?.rates, { USD: 3.7, THB: 0.1 });
  assertEquals(mergeRates(null, fallback)?.source, "frankfurter");
});
