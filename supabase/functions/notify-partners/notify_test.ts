import { assert, assertEquals } from "jsr:@std/assert@1";
import { apnsHost, isInvalidToken, providerToken, sendPush } from "./apns.ts";
import { firstName, formatAmount, partnerAlert } from "./message.ts";

const LRI = "⁦";
const PDI = "⁩";

Deno.test("formats amounts with the sign first, isolated left to right", () => {
  assertEquals(formatAmount(212.4, "ILS"), `${LRI}₪212.40${PDI}`);
  assertEquals(formatAmount(1250, "ILS"), `${LRI}₪1,250${PDI}`);
  assertEquals(formatAmount(12.99, "USD"), `${LRI}$12.99${PDI}`);
  assertEquals(formatAmount(40, "CZK"), `${LRI}CZK 40${PDI}`);
});

Deno.test("uses the first name", () => {
  assertEquals(firstName("  מיכל כהן "), "מיכל");
  assertEquals(firstName(""), "");
});

Deno.test("builds a gender-neutral alert for an expense", () => {
  const alert = partnerAlert({
    authorName: "מיכל כהן",
    kind: "expense",
    merchant: "רמי לוי",
    categoryName: "סופר",
    categoryEmoji: "🛒",
    amount: 212.4,
    currency: "ILS",
  });
  assertEquals(alert.title, "הוצאה חדשה ממיכל");
  assertEquals(alert.body, `🛒 רמי לוי · ${LRI}₪212.40${PDI}`);
});

Deno.test("falls back to the category, then to a generic word", () => {
  const byCategory = partnerAlert({
    authorName: "Dana", kind: "income", merchant: " ", categoryName: "משכורת", categoryEmoji: null,
    amount: 100, currency: "ILS",
  });
  assertEquals(byCategory.title, "הכנסה חדשה מDana");
  assertEquals(byCategory.body, `משכורת · ${LRI}₪100${PDI}`);

  const bare = partnerAlert({
    authorName: "", kind: "expense", merchant: null, categoryName: null, categoryEmoji: null,
    amount: 5, currency: "EUR",
  });
  assertEquals(bare.title, "הוצאה חדשה מהשותף");
  assertEquals(bare.body, `הוצאה · ${LRI}€5${PDI}`);
});

async function testConfig() {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]) as CryptoKeyPair;
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let binary = "";
  for (const byte of der) binary += String.fromCharCode(byte);
  const keyPem = `-----BEGIN PRIVATE KEY-----\n${btoa(binary).replace(/(.{64})/g, "$1\n")}\n-----END PRIVATE KEY-----`;
  return { pair, config: { keyPem, keyId: "ABC123DEFG", teamId: "TEAM123456", topic: "com.bignono97.snapay" } };
}

function base64urlDecode(text: string): Uint8Array<ArrayBuffer> {
  const padded = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

Deno.test("signs an ES256 provider token APNs can verify", async () => {
  const { pair, config } = await testConfig();
  const token = await providerToken(config, new Date("2026-10-01T12:00:00Z"));
  const [header, claims, signature] = token.split(".");
  assertEquals(JSON.parse(new TextDecoder().decode(base64urlDecode(header))), { alg: "ES256", kid: "ABC123DEFG" });
  assertEquals(JSON.parse(new TextDecoder().decode(base64urlDecode(claims))), { iss: "TEAM123456", iat: 1790856000 });
  const signatureBytes = base64urlDecode(signature);
  assertEquals(signatureBytes.length, 64);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    pair.publicKey,
    signatureBytes,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  assert(valid);
});

Deno.test("recognises tokens that will never work again", () => {
  assert(isInvalidToken(410, "Unregistered"));
  assert(isInvalidToken(400, "BadDeviceToken"));
  assert(!isInvalidToken(400, "PayloadTooLarge"));
  assert(!isInvalidToken(500, undefined));
  assertEquals(apnsHost("sandbox"), "https://api.sandbox.push.apple.com");
  assertEquals(apnsHost("production"), "https://api.push.apple.com");
});

Deno.test("sends to the right host with the APNs headers", async () => {
  const { config } = await testConfig();
  const calls: { url: string; init: RequestInit }[] = [];
  const fakeFetch = ((url: string, init: RequestInit) => {
    calls.push({ url, init });
    return Promise.resolve(new Response(JSON.stringify({ reason: "BadDeviceToken" }), { status: 400 }));
  }) as unknown as typeof fetch;
  const result = await sendPush("abcd", "sandbox", { aps: {} }, "jwt", config, fakeFetch);
  assertEquals(result, "invalid_token");
  assertEquals(calls[0].url, "https://api.sandbox.push.apple.com/3/device/abcd");
  const headers = calls[0].init.headers as Record<string, string>;
  assertEquals(headers["apns-topic"], "com.bignono97.snapay");
  assertEquals(headers["apns-push-type"], "alert");
  assertEquals(headers.authorization, "bearer jwt");
});
