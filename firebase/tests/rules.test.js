// Security rules for SnaPay's Firestore data. Run with `npm test` in firebase/ (starts the
// emulator). The fixture: מיכל owns a shared household with אבי; דנה has her own household and
// a pending invite to theirs; ערן has nothing to do with any of them.

import { after, before, beforeEach, describe, test } from "node:test";
import { readFileSync } from "node:fs";
import { assertFails, assertSucceeds, initializeTestEnvironment } from "@firebase/rules-unit-testing";
import {
  collection, deleteDoc, deleteField, doc, getDoc, getDocs, orderBy, query, setDoc, updateDoc, where, writeBatch,
} from "firebase/firestore";

const SHARED = "11111111-1111-1111-1111-111111111111";
const DANA_HOME = "22222222-2222-2222-2222-222222222222";
const AVI_NEW = "33333333-3333-3333-3333-333333333333";
const users = {
  michal: { uid: "uid-michal", id: "AAAAAAAA-0000-0000-0000-000000000001", email: "michal@example.com" },
  avi: { uid: "uid-avi", id: "AAAAAAAA-0000-0000-0000-000000000002", email: "avi@example.com" },
  dana: { uid: "uid-dana", id: "AAAAAAAA-0000-0000-0000-000000000003", email: "dana@example.com" },
  eran: { uid: "uid-eran", id: "AAAAAAAA-0000-0000-0000-000000000004", email: "eran@example.com" },
};
const inviteID = `${SHARED}_${users.dana.email}`;

let env;

function db(user, { verified = true } = {}) {
  return env.authenticatedContext(user.uid, { email: user.email, email_verified: verified }).firestore();
}

function member(user, joinedAt, extra = {}) {
  return { user_id: user.id, full_name: user.uid, joined_at: joinedAt, ...extra };
}

function transaction(id, user, householdID, occurredAt = "2026-10-01T09:00:00.000Z") {
  return {
    id, household_id: householdID, user_id: user.id, kind: "expense", amount: 18.5, currency: "ILS",
    original_amount: 18.5, original_currency: "ILS", exchange_rate: 1, fee_amount: 0,
    occurred_at: occurredAt, source: "manual",
  };
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-snapay",
    firestore: { rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8") },
  });
});

after(async () => {
  await env.cleanup();
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    for (const user of Object.values(users)) {
      await setDoc(doc(admin, "user_ids", user.id), { uid: user.uid });
    }
    await setDoc(doc(admin, "households", SHARED), {
      id: SHARED, name: "הבית", is_shared: true, owner_uid: users.michal.uid,
      members: {
        [users.michal.uid]: member(users.michal, "2026-09-01T00:00:00.000Z"),
        [users.avi.uid]: member(users.avi, "2026-09-10T00:00:00.000Z"),
      },
    });
    await setDoc(doc(admin, "households", DANA_HOME), {
      id: DANA_HOME, name: "דנה", is_shared: false, owner_uid: users.dana.uid,
      members: { [users.dana.uid]: member(users.dana, "2026-09-05T00:00:00.000Z") },
    });
    await setDoc(doc(admin, "profiles", users.avi.uid), { id: users.avi.id, full_name: "אבי", active_household_id: SHARED });
    await setDoc(doc(admin, "transactions", "T-MICHAL"), transaction("T-MICHAL", users.michal, SHARED));
    await setDoc(doc(admin, "transactions", "T-AVI"), transaction("T-AVI", users.avi, SHARED));
    await setDoc(doc(admin, "transactions", "T-DANA"), transaction("T-DANA", users.dana, DANA_HOME));
    await setDoc(doc(admin, "categories", "C-SUPER"), { id: "C-SUPER", household_id: SHARED, name: "סופר", kind: "expense" });
    await setDoc(doc(admin, "invites", inviteID), {
      id: "INVITE-1", household_id: SHARED, email: users.dana.email, status: "pending",
      created_at: "2026-09-30T10:00:00.000Z", invited_by: users.michal.uid, inviter_name: "מיכל",
    });
  });
});

function householdTransactions(firestore, householdID) {
  return getDocs(query(
    collection(firestore, "transactions"),
    where("household_id", "==", householdID),
    orderBy("occurred_at", "desc"),
  ));
}

describe("sign-up", () => {
  test("a new user creates their id, personal household and profile in one batch", async () => {
    const newcomer = { uid: "uid-new", id: "AAAAAAAA-0000-0000-0000-000000000009", email: "new@example.com" };
    const home = "44444444-4444-4444-4444-444444444444";
    const firestore = db(newcomer, { verified: false });
    const batch = writeBatch(firestore);
    batch.set(doc(firestore, "user_ids", newcomer.id), { uid: newcomer.uid });
    batch.set(doc(firestore, "households", home), {
      id: home, name: "חדש", is_shared: false, owner_uid: newcomer.uid,
      members: { [newcomer.uid]: member(newcomer, "2026-10-01T00:00:00.000Z") },
    });
    batch.set(doc(firestore, "profiles", newcomer.uid), { id: newcomer.id, full_name: "חדש", active_household_id: home });
    await assertSucceeds(batch.commit());
  });

  test("nobody takes over an existing user id", async () => {
    await assertFails(setDoc(doc(db(users.eran), "user_ids", users.michal.id), { uid: users.eran.uid }));
  });

  test("a household can't be created in someone else's name", async () => {
    const home = "55555555-5555-5555-5555-555555555555";
    await assertFails(setDoc(doc(db(users.eran), "households", home), {
      id: home, name: "x", is_shared: false, owner_uid: users.eran.uid,
      members: { [users.eran.uid]: member(users.michal, "2026-10-01T00:00:00.000Z") },
    }));
  });

  test("a profile can only point at a household its owner is in", async () => {
    await assertFails(updateDoc(doc(db(users.avi), "profiles", users.avi.uid), { active_household_id: DANA_HOME }));
    await assertSucceeds(updateDoc(doc(db(users.avi), "profiles", users.avi.uid), { full_name: "אבי לוי" }));
  });
});

describe("household data", () => {
  test("members read the household's transactions; others don't", async () => {
    await assertSucceeds(householdTransactions(db(users.avi), SHARED));
    await assertFails(householdTransactions(db(users.dana), SHARED));
    await assertFails(getDoc(doc(db(users.eran), "transactions", "T-MICHAL")));
  });

  test("each member writes only their own transactions", async () => {
    const avi = db(users.avi);
    await assertSucceeds(updateDoc(doc(avi, "transactions", "T-AVI"), { amount: 20 }));
    await assertFails(updateDoc(doc(avi, "transactions", "T-MICHAL"), { amount: 20 }));
    await assertFails(deleteDoc(doc(avi, "transactions", "T-MICHAL")));
    await assertSucceeds(setDoc(doc(avi, "transactions", "T-NEW"), transaction("T-NEW", users.avi, SHARED)));
    await assertFails(setDoc(doc(avi, "transactions", "T-FAKE"), transaction("T-FAKE", users.michal, SHARED)));
    await assertFails(setDoc(doc(avi, "transactions", "T-ELSEWHERE"), transaction("T-ELSEWHERE", users.avi, DANA_HOME)));
    await assertFails(updateDoc(doc(avi, "transactions", "T-AVI"), { user_id: users.michal.id }));
  });

  test("the app's other queries pass the rules", async () => {
    const avi = db(users.avi);
    await assertSucceeds(setDoc(doc(avi, "recurring_rules", "R-AVI"), {
      id: "R-AVI", household_id: SHARED, user_id: users.avi.id, is_active: true, amount: 50, frequency: "monthly",
    }));
    // Recurring charges by user; quick-log duplicates; merchant history.
    await assertSucceeds(getDocs(query(collection(avi, "recurring_rules"), where("user_id", "==", users.avi.id), where("is_active", "==", true))));
    await assertSucceeds(getDocs(query(collection(avi, "transactions"), where("household_id", "==", SHARED),
      where("source", "==", "apple_pay"), where("external_id", "==", "applepay-1"))));
    await assertSucceeds(setDoc(doc(avi, "merchant_map", "M-1"), { household_id: SHARED, merchant_key: "ארומה", category_id: "C-SUPER", times_used: 1 }, { merge: true }));
    await assertSucceeds(getDocs(query(collection(avi, "merchant_map"), where("household_id", "==", SHARED))));
    await assertFails(getDocs(query(collection(db(users.dana), "merchant_map"), where("household_id", "==", SHARED))));
    await assertFails(getDocs(query(collection(db(users.dana), "recurring_rules"), where("user_id", "==", users.avi.id))));
  });

  test("members manage the household's categories", async () => {
    await assertSucceeds(setDoc(doc(db(users.avi), "categories", "C-NEW"), { id: "C-NEW", household_id: SHARED, name: "קפה" }));
    await assertFails(setDoc(doc(db(users.dana), "categories", "C-HACK"), { id: "C-HACK", household_id: SHARED, name: "x" }));
    await assertFails(updateDoc(doc(db(users.avi), "categories", "C-SUPER"), { household_id: DANA_HOME }));
  });
});

describe("joining", () => {
  async function join(user, options) {
    await updateDoc(doc(db(user, options), "households", SHARED), {
      [`members.${user.uid}`]: member(user, "2026-10-01T00:00:00.000Z"),
    });
  }

  test("an invited user with a verified email joins", async () => {
    await assertSucceeds(join(users.dana));
    await assertSucceeds(updateDoc(doc(db(users.dana), "invites", inviteID), { status: "accepted" }));
    await assertSucceeds(householdTransactions(db(users.dana), SHARED));
  });

  test("an unverified email can't use the invite", async () => {
    await assertFails(join(users.dana, { verified: false }));
  });

  test("nobody joins without an invite, or after it's revoked", async () => {
    await assertFails(join(users.eran));
    await env.withSecurityRulesDisabled((context) =>
      updateDoc(doc(context.firestore(), "invites", inviteID), { status: "revoked" }));
    await assertFails(join(users.dana));
  });

  test("a joining user can't touch anyone else's entry", async () => {
    await assertFails(updateDoc(doc(db(users.dana), "households", SHARED), {
      [`members.${users.dana.uid}`]: member(users.dana, "2026-10-01T00:00:00.000Z"),
      owner_uid: users.dana.uid,
    }));
  });
});

describe("invites", () => {
  test("members invite with the household-and-email id", async () => {
    const avi = db(users.avi);
    const invite = { id: "INVITE-2", household_id: SHARED, email: "eran@example.com", status: "pending", invited_by: users.avi.uid, inviter_name: "אבי" };
    await assertSucceeds(setDoc(doc(avi, "invites", `${SHARED}_eran@example.com`), invite));
    await assertFails(setDoc(doc(avi, "invites", "made-up-id"), invite));
    await assertFails(setDoc(doc(db(users.dana), "invites", `${SHARED}_x@example.com`), { ...invite, email: "x@example.com", invited_by: users.dana.uid }));
  });

  test("the invitee sees and answers their invite, and nothing else", async () => {
    const dana = db(users.dana);
    await assertSucceeds(getDocs(query(collection(dana, "invites"), where("email", "==", users.dana.email), where("status", "==", "pending"))));
    await assertFails(getDocs(query(collection(dana, "invites"), where("household_id", "==", SHARED))));
    await assertFails(updateDoc(doc(dana, "invites", inviteID), { status: "accepted", email: "other@example.com" }));
    await assertSucceeds(updateDoc(doc(dana, "invites", inviteID), { status: "declined" }));
    await assertFails(updateDoc(doc(db(users.eran), "invites", inviteID), { status: "accepted" }));
  });

  test("members revoke", async () => {
    await assertSucceeds(updateDoc(doc(db(users.avi), "invites", inviteID), { status: "revoked" }));
  });
});

describe("leaving and removal", () => {
  test("a member leaves by removing their own entry, and can't remove others", async () => {
    const avi = db(users.avi);
    await assertFails(updateDoc(doc(avi, "households", SHARED), { [`members.${users.michal.uid}`]: deleteField() }));
    await assertSucceeds(updateDoc(doc(avi, "households", SHARED), { [`members.${users.avi.uid}`]: deleteField(), is_shared: false }));
  });

  test("only the owner removes members, and never adds them", async () => {
    await assertFails(updateDoc(doc(db(users.avi), "households", SHARED), { [`members.${users.michal.uid}.removed`]: true }));
    await assertSucceeds(updateDoc(doc(db(users.michal), "households", SHARED), { [`members.${users.avi.uid}.removed`]: true }));
    await assertFails(updateDoc(doc(db(users.michal), "households", SHARED), {
      [`members.${users.eran.uid}`]: member(users.eran, "2026-10-01T00:00:00.000Z"),
    }));
  });

  test("a removed member keeps only what they need to move out", async () => {
    await env.withSecurityRulesDisabled((context) =>
      updateDoc(doc(context.firestore(), "households", SHARED), { [`members.${users.avi.uid}.removed`]: true }));
    const avi = db(users.avi);
    await assertFails(householdTransactions(avi, SHARED));
    await assertFails(setDoc(doc(avi, "transactions", "T-LATE"), transaction("T-LATE", users.avi, SHARED)));
    await assertFails(updateDoc(doc(avi, "households", SHARED), { [`members.${users.avi.uid}.removed`]: false }));
    // Reads own rows and the categories, moves to a new household of their own, then leaves.
    await assertSucceeds(getDocs(query(collection(avi, "transactions"), where("user_id", "==", users.avi.id), where("household_id", "==", SHARED))));
    await assertSucceeds(getDocs(query(collection(avi, "categories"), where("household_id", "==", SHARED))));
    await assertSucceeds(setDoc(doc(avi, "households", AVI_NEW), {
      id: AVI_NEW, name: "אבי", is_shared: false, owner_uid: users.avi.uid,
      members: { [users.avi.uid]: member(users.avi, "2026-10-01T00:00:00.000Z") },
    }));
    await assertSucceeds(updateDoc(doc(avi, "transactions", "T-AVI"), { household_id: AVI_NEW }));
    await assertSucceeds(updateDoc(doc(avi, "profiles", users.avi.uid), { active_household_id: AVI_NEW }));
    await assertSucceeds(updateDoc(doc(avi, "households", SHARED), { [`members.${users.avi.uid}`]: deleteField() }));
  });

  test("the owner hands over ownership when leaving, and deletes the household only when alone", async () => {
    const michal = db(users.michal);
    await assertFails(deleteDoc(doc(michal, "households", SHARED)));
    await assertFails(updateDoc(doc(michal, "households", SHARED), { [`members.${users.michal.uid}`]: deleteField() }));
    await assertSucceeds(updateDoc(doc(michal, "households", SHARED), {
      [`members.${users.michal.uid}`]: deleteField(), owner_uid: users.avi.uid, is_shared: false,
    }));
    await assertSucceeds(deleteDoc(doc(db(users.dana), "households", DANA_HOME)));
  });
});
