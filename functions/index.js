const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { RtcTokenBuilder, RtcRole } = require("agora-token");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

const AGORA_APP_ID = "b959d814f9e04c70aa7c5d1808bb434f";
const AGORA_APP_CERTIFICATE = defineSecret("AGORA_APP_CERTIFICATE");
const TOKEN_LIFETIME_SECONDS = 3600;
const COINS_PER_EGP = 2; // 100 coins = 50 EGP
const MIN_WITHDRAWAL_EGP = 50;
const PLATFORM_LIVE_SHARE = 0.20; // platform gets 20%; creator receives 80%

function requireAuth(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "سجل الدخول أولًا");
  return request.auth.uid;
}

function isAdmin(request) {
  return request.auth && request.auth.token && request.auth.token.admin === true;
}

function positiveInteger(value, field) {
  const number = Number(value);
  if (!Number.isInteger(number) || number <= 0) {
    throw new HttpsError("invalid-argument", `${field} يجب أن يكون رقمًا صحيحًا موجبًا`);
  }
  return number;
}

exports.getAgoraToken = onCall(
  { secrets: [AGORA_APP_CERTIFICATE], region: "us-central1" },
  (request) => {
    const uid = requireAuth(request);
    const channelName = request.data && request.data.channelName;
    const wantsBroadcast = request.data && request.data.role === "broadcaster";
    if (typeof channelName !== "string" || channelName.length === 0 || channelName.length > 64) {
      throw new HttpsError("invalid-argument", "اسم القناة غير صالح");
    }
    if (wantsBroadcast && channelName !== `live_${uid}`) {
      throw new HttpsError("permission-denied", "مسموح لك بالبث على قناتك فقط");
    }
    const role = wantsBroadcast ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER;
    const token = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID,
      AGORA_APP_CERTIFICATE.value(),
      channelName,
      0,
      role,
      TOKEN_LIFETIME_SECONDS,
      TOKEN_LIFETIME_SECONDS
    );
    return { token };
  }
);

// Creates a wallet lazily. Client apps can read the wallet but cannot write its balance.
exports.getWallet = onCall({ region: "us-central1" }, async (request) => {
  const uid = requireAuth(request);
  const ref = db.collection("wallets").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set({ availableCoins: 0, pendingCoins: 0, lifetimeEarnedCoins: 0, updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    return { availableCoins: 0, pendingCoins: 0, lifetimeEarnedCoins: 0, coinsPerEgp: COINS_PER_EGP };
  }
  return { ...snap.data(), coinsPerEgp: COINS_PER_EGP };
});

exports.getPlatformWallet = onCall({ region: "us-central1" }, async (request) => {
  if (!isAdmin(request)) throw new HttpsError("permission-denied", "هذه العملية لمالك التطبيق فقط");
  const snap = await db.collection("wallets").doc("__platform__").get();
  return { ...(snap.exists ? snap.data() : { availableCoins: 0, lifetimeEarnedCoins: 0 }), coinsPerEgp: COINS_PER_EGP };
});

// A viewer spends coins; the creator gets 80% and the platform wallet gets 20% atomically.
exports.sendLiveGift = onCall({ region: "us-central1" }, async (request) => {
  const senderUid = requireAuth(request);
  const hostUid = request.data && request.data.hostUid;
  const coins = positiveInteger(request.data && request.data.coins, "قيمة الهدية");
  if (typeof hostUid !== "string" || hostUid.length < 10 || hostUid === senderUid) {
    throw new HttpsError("invalid-argument", "صاحب البث غير صالح");
  }
  const platformCoins = Math.floor(coins * PLATFORM_LIVE_SHARE);
  const creatorCoins = coins - platformCoins;
  if (creatorCoins < 1) throw new HttpsError("invalid-argument", "قيمة الهدية صغيرة جدًا");
  const senderRef = db.collection("wallets").doc(senderUid);
  const hostRef = db.collection("wallets").doc(hostUid);
  const platformRef = db.collection("wallets").doc("__platform__");
  const giftRef = db.collection("giftTransactions").doc();
  await db.runTransaction(async (tx) => {
    const senderSnap = await tx.get(senderRef);
    const sender = senderSnap.exists ? senderSnap.data() : {};
    const available = Number(sender.availableCoins || 0);
    if (available < coins) throw new HttpsError("failed-precondition", "رصيد العملات غير كافٍ");
    const hostSnap = await tx.get(hostRef);
    const host = hostSnap.exists ? hostSnap.data() : {};
    const platformSnap = await tx.get(platformRef);
    const platform = platformSnap.exists ? platformSnap.data() : {};
    tx.set(senderRef, {
      availableCoins: available - coins,
      pendingCoins: Number(sender.pendingCoins || 0),
      lifetimeSpentCoins: Number(sender.lifetimeSpentCoins || 0) + coins,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.set(hostRef, {
      availableCoins: Number(host.availableCoins || 0) + creatorCoins,
      pendingCoins: Number(host.pendingCoins || 0),
      lifetimeEarnedCoins: Number(host.lifetimeEarnedCoins || 0) + creatorCoins,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.set(platformRef, {
      availableCoins: Number(platform.availableCoins || 0) + platformCoins,
      lifetimeEarnedCoins: Number(platform.lifetimeEarnedCoins || 0) + platformCoins,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.set(giftRef, {
      senderUid,
      hostUid,
      spentCoins: coins,
      creatorCoins,
      platformCoins,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { spentCoins: coins, creatorCoins, platformCoins };
});

// Creates a withdrawal request and locks the requested coins until an admin pays/rejects it.
exports.requestWithdrawal = onCall({ region: "us-central1" }, async (request) => {
  const uid = requireAuth(request);
  const amountEgp = positiveInteger(request.data && request.data.amountEgp, "مبلغ السحب");
  const method = request.data && request.data.method;
  const destination = String((request.data && request.data.destination) || "").trim();
  if (!['instapay', 'wallet'].includes(method)) throw new HttpsError("invalid-argument", "طريقة السحب غير مدعومة");
  if (!destination || destination.length < 6 || destination.length > 120) throw new HttpsError("invalid-argument", "بيانات الاستلام غير صالحة");
  if (amountEgp < MIN_WITHDRAWAL_EGP) throw new HttpsError("failed-precondition", `الحد الأدنى للسحب ${MIN_WITHDRAWAL_EGP} جنيه`);
  const coins = amountEgp * COINS_PER_EGP;
  const walletRef = db.collection("wallets").doc(uid);
  const requestRef = db.collection("withdrawalRequests").doc();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(walletRef);
    const wallet = snap.exists ? snap.data() : {};
    const available = Number(wallet.availableCoins || 0);
    if (available < coins) throw new HttpsError("failed-precondition", "الرصيد غير كافٍ");
    tx.set(walletRef, {
      availableCoins: available - coins,
      pendingCoins: Number(wallet.pendingCoins || 0) + coins,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.set(requestRef, {
      uid,
      amountEgp,
      coins,
      method,
      destination,
      status: "pending",
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
  return { requestId: requestRef.id, status: "pending", amountEgp, coins };
});

// Admin-only credit endpoint for verified ad-network server callbacks. Never call this from the client.
exports.creditVerifiedAdRevenue = onCall({ region: "us-central1" }, async (request) => {
  if (!isAdmin(request)) throw new HttpsError("permission-denied", "هذه العملية للإدارة فقط");
  const uid = request.data && request.data.uid;
  const amountEgp = Number(request.data && request.data.amountEgp);
  if (typeof uid !== "string" || !Number.isFinite(amountEgp) || amountEgp <= 0) throw new HttpsError("invalid-argument", "بيانات إعلان غير صالحة");
  const coins = Math.floor(amountEgp * COINS_PER_EGP);
  const walletRef = db.collection("wallets").doc(uid);
  const eventRef = db.collection("adRevenueEvents").doc(String(request.data.eventId || ""));
  if (eventRef.id.length < 5) throw new HttpsError("invalid-argument", "eventId مطلوب لمنع التكرار");
  await db.runTransaction(async (tx) => {
    const event = await tx.get(eventRef);
    if (event.exists) return;
    const walletSnap = await tx.get(walletRef);
    const wallet = walletSnap.exists ? walletSnap.data() : {};
    tx.set(walletRef, {
      availableCoins: Number(wallet.availableCoins || 0) + coins,
      pendingCoins: Number(wallet.pendingCoins || 0),
      lifetimeEarnedCoins: Number(wallet.lifetimeEarnedCoins || 0) + coins,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.create(eventRef, { uid, amountEgp, creditedCoins: coins, createdAt: admin.firestore.FieldValue.serverTimestamp() });
  });
  return { creditedCoins: coins };
});

exports.adminUpdateWithdrawal = onCall({ region: "us-central1" }, async (request) => {
  if (!isAdmin(request)) throw new HttpsError("permission-denied", "هذه العملية للإدارة فقط");
  const requestId = request.data && request.data.requestId;
  const status = request.data && request.data.status;
  if (typeof requestId !== "string" || !['paid', 'rejected'].includes(status)) throw new HttpsError("invalid-argument", "بيانات الطلب غير صالحة");
  const requestRef = db.collection("withdrawalRequests").doc(requestId);
  await db.runTransaction(async (tx) => {
    const requestSnap = await tx.get(requestRef);
    if (!requestSnap.exists) throw new HttpsError("not-found", "طلب السحب غير موجود");
    const item = requestSnap.data();
    if (item.status !== "pending") throw new HttpsError("failed-precondition", "تمت معالجة الطلب من قبل");
    const walletRef = db.collection("wallets").doc(item.uid);
    const walletSnap = await tx.get(walletRef);
    const wallet = walletSnap.exists ? walletSnap.data() : {};
    const pending = Math.max(0, Number(wallet.pendingCoins || 0) - Number(item.coins || 0));
    const refund = status === "rejected" ? Number(item.coins || 0) : 0;
    tx.set(walletRef, {
      availableCoins: Number(wallet.availableCoins || 0) + refund,
      pendingCoins: pending,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    tx.update(requestRef, { status, processedAt: admin.firestore.FieldValue.serverTimestamp() });
  });
  return { requestId, status };
});
