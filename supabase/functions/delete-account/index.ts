// Permanently deletes the calling user's account and everything they entered.
//
// The database cascades from auth.users: profile, memberships, transactions, recurring rules,
// goal contributions and device tokens are deleted; a household left empty is deleted with all its
// data, and a shared household left without an owner passes ownership to the remaining partner.
// Receipt photos live in Storage under "receipts/<user id>/…" and are removed here first.
//
// POST /functions/v1/delete-account with the user's access token. No body.

import { createClient } from "npm:@supabase/supabase-js@2";

const RECEIPTS_BUCKET = "receipts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const authorization = req.headers.get("Authorization");
  if (!authorization) {
    return json({ error: "unauthorized" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) {
    return json({ error: "server_misconfigured" }, 500);
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
  const userId = userData.user.id;

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });

  // Remove receipt photos. A missing bucket just means there is nothing to remove yet.
  const storageError = await removeReceipts(admin, userId);
  if (storageError) {
    console.error("delete-account: receipts cleanup failed", storageError);
    return json({ error: "storage_cleanup_failed" }, 500);
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    console.error("delete-account: deleteUser failed", deleteError);
    return json({ error: "delete_failed" }, 500);
  }

  return json({ deleted: true });
});

// deno-lint-ignore no-explicit-any
async function removeReceipts(admin: any, userId: string): Promise<string | null> {
  const bucket = admin.storage.from(RECEIPTS_BUCKET);
  for (;;) {
    const { data, error } = await bucket.list(userId, { limit: 100 });
    if (error) {
      return /not found/i.test(error.message ?? "") ? null : String(error.message ?? error);
    }
    if (!data || data.length === 0) return null;
    const paths = data.map((file: { name: string }) => `${userId}/${file.name}`);
    const { error: removeError } = await bucket.remove(paths);
    if (removeError) return String(removeError.message ?? removeError);
  }
}
