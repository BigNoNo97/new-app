// Tells the other members of a shared household that someone logged a transaction.
//
// POST /functions/v1/notify-partners with the author's access token and { "transaction_id": "…" }.
// The app calls it after a new transaction reaches the server (including ones queued offline).
// Each transaction is notified at most once (transactions.partners_notified_at), only by its
// author, and only within a day of being created. Partners who turned the notification off are
// skipped; device tokens APNs rejects for good are deleted.
//
// Secrets: APNS_KEY (the .p8 file contents), APNS_KEY_ID, APNS_TEAM_ID; APNS_TOPIC defaults to
// the app's bundle id. Without them the function answers { skipped: "apns_not_configured" }.

import { createClient } from "npm:@supabase/supabase-js@2";
import { type ApnsConfig, type ApnsEnvironment, providerToken, sendPush } from "./apns.ts";
import { partnerAlert } from "./message.ts";

const MAX_AGE_MS = 24 * 60 * 60 * 1000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function apnsConfig(): ApnsConfig | null {
  const keyPem = Deno.env.get("APNS_KEY");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  if (!keyPem || !keyId || !teamId) return null;
  return { keyPem, keyId, teamId, topic: Deno.env.get("APNS_TOPIC") ?? "com.bignono97.snapay" };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }
  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    return json({ error: "unauthorized" }, 401);
  }

  let transactionId: string | undefined;
  try {
    transactionId = (await req.json())?.transaction_id;
  } catch {
    transactionId = undefined;
  }
  if (!transactionId || !/^[0-9a-f-]{36}$/i.test(transactionId)) {
    return json({ error: "bad_request" }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    return json({ error: "server_misconfigured" }, 500);
  }
  const config = apnsConfig();
  if (!config) {
    return json({ skipped: "apns_not_configured" });
  }

  // Identify the caller from their own token; never trust a user id from the request.
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return json({ error: "unauthorized" }, 401);
  }
  const authorId = userData.user.id;
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  // Claim the transaction: only its author, only once, only while it's fresh.
  const { data: claimed, error: claimError } = await admin
    .from("transactions")
    .update({ partners_notified_at: new Date().toISOString() })
    .eq("id", transactionId)
    .eq("user_id", authorId)
    .is("partners_notified_at", null)
    .gte("created_at", new Date(Date.now() - MAX_AGE_MS).toISOString())
    .select("household_id, kind, merchant, amount, currency, category_id")
    .maybeSingle();
  if (claimError) {
    console.error("notify-partners: claim failed", claimError);
    return json({ error: "claim_failed" }, 500);
  }
  if (!claimed) {
    return json({ notified: 0, reason: "not_eligible" });
  }

  const { data: members } = await admin
    .from("household_members")
    .select("user_id")
    .eq("household_id", claimed.household_id)
    .neq("user_id", authorId);
  const memberIds = (members ?? []).map((row: { user_id: string }) => row.user_id);
  if (memberIds.length === 0) {
    return json({ notified: 0, reason: "no_partners" });
  }

  const { data: recipients } = await admin
    .from("profiles")
    .select("id")
    .in("id", memberIds)
    .eq("notify_partner_activity", true);
  const recipientIds = (recipients ?? []).map((row: { id: string }) => row.id);
  const { data: tokens } = recipientIds.length === 0
    ? { data: [] }
    : await admin.from("device_tokens").select("token, environment").in("user_id", recipientIds);
  if (!tokens || tokens.length === 0) {
    return json({ notified: 0, reason: "no_devices" });
  }

  const [{ data: author }, { data: category }] = await Promise.all([
    admin.from("profiles").select("full_name").eq("id", authorId).maybeSingle(),
    claimed.category_id
      ? admin.from("categories").select("name, emoji").eq("id", claimed.category_id).maybeSingle()
      : Promise.resolve({ data: null }),
  ]);

  const alert = partnerAlert({
    authorName: author?.full_name ?? "",
    kind: claimed.kind,
    merchant: claimed.merchant,
    categoryName: category?.name ?? null,
    categoryEmoji: category?.emoji ?? null,
    amount: Number(claimed.amount),
    currency: claimed.currency,
  });
  const payload = {
    aps: { alert, sound: "default", "thread-id": "partner-activity" },
    transaction_id: transactionId,
  };

  const jwt = await providerToken(config);
  let sent = 0;
  const invalid: string[] = [];
  await Promise.all(
    tokens.map(async (row: { token: string; environment: ApnsEnvironment }) => {
      try {
        const result = await sendPush(row.token, row.environment, payload, jwt, config);
        if (result === "sent") sent += 1;
        if (result === "invalid_token") invalid.push(row.token);
      } catch (error) {
        console.error("notify-partners: send failed", error);
      }
    }),
  );
  if (invalid.length > 0) {
    await admin.from("device_tokens").delete().in("token", invalid);
  }
  return json({ notified: sent });
});
