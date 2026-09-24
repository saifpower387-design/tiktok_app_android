const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { RtcTokenBuilder, RtcRole } = require("agora-token");

const AGORA_APP_ID = "b959d814f9e04c70aa7c5d1808bb434f";
const AGORA_APP_CERTIFICATE = defineSecret("AGORA_APP_CERTIFICATE");

const TOKEN_LIFETIME_SECONDS = 3600;

exports.getAgoraToken = onCall(
  { secrets: [AGORA_APP_CERTIFICATE], region: "us-central1" },
  (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "سجل الدخول أولًا");
    }
    const uid = request.auth.uid;
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