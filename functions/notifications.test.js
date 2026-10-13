const test = require("node:test");
const assert = require("node:assert/strict");

// Stub firebase-admin before notifications.js loads it.
const writes = [];
const sent = [];
const userUpdates = [];
const users = {
  hero1: { fcmToken: "good", fcmTokens: ["dead"] },
  noToken: {},
};
const ref = (col, id) => ({ col, id, get: (f) => users[id]?.[f] });
const fieldValue = {
  serverTimestamp: () => "TS",
  delete: () => "DELETE",
  arrayRemove: (...v) => ({ arrayRemove: v }),
};
const db = {
  collection: (col) => ({ doc: (id = "auto") => ref(col, id) }),
  batch: () => ({ set: (r, d) => writes.push(d), commit: async () => {} }),
  getAll: async (...refs) =>
    refs.map((r) => ({ id: r.id, exists: r.id in users, data: () => users[r.id] })),
  runTransaction: async (fn) =>
    fn({ get: async (r) => ({ get: (f) => users[r.id][f] }), update: (r, d) => userUpdates.push([r.id, d]) }),
};
const firestore = () => db;
firestore.FieldValue = fieldValue;
const admin = {
  firestore,
  messaging: () => ({
    send: async (msg) => {
      sent.push(msg);
      if (msg.token === "dead") {
        throw Object.assign(new Error("gone"), { code: "messaging/registration-token-not-registered" });
      }
      return "id";
    },
  }),
};
require.cache[require.resolve("firebase-admin")] = { exports: admin };

const { sendNotificationToUsers, sellerStatusMessage } = require("./notifications");

test("writes inbox for every user, pushes per token, cleans dead tokens", async () => {
  await sendNotificationToUsers(
    ["hero1", "noToken", "", undefined],
    { title: "T", body: "B" },
    { type: "chat_message", chatId: "c1", targetScreen: undefined },
  );

  assert.equal(writes.length, 2, "inbox written even for users without tokens");
  assert.deepEqual(writes[0].data, { type: "chat_message", chatId: "c1" }, "no 'undefined' strings");

  assert.deepEqual(sent.map((m) => m.token).sort(), ["dead", "good"]);
  assert.equal(sent[0].android.notification.channelId, "chat_messages");
  assert.equal(sent[0].android.notification.tag, "chat_c1");

  assert.equal(userUpdates.length, 1);
  assert.equal(userUpdates[0][0], "hero1");
  assert.deepEqual(userUpdates[0][1].fcmTokens, { arrayRemove: ["dead"] });
  assert.equal(userUpdates[0][1].fcmToken, undefined, "live single token kept");
});

test("sellers hear about new paid orders and cancels, not rider releases", () => {
  assert.ok(sellerStatusMessage("pending_payment", "queued"));
  assert.ok(sellerStatusMessage("paid", "queued"));
  assert.equal(sellerStatusMessage("assigned", "queued"), null);
  assert.ok(sellerStatusMessage("assigned", "canceled"));
  assert.equal(sellerStatusMessage("pending_payment", "canceled"), null);
});
