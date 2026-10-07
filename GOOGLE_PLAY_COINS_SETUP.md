# شحن العملات عبر Google Play

تمت إضافة مسار شراء آمن للباقات التالية:

| Product ID | العملات | السعر المطلوب في Google Play |
|---|---:|---:|
| `coins_100` | 100 | 62 EGP |
| `coins_500` | 500 | 310 EGP |
| `coins_1000` | 1000 | 620 EGP |

> التطبيق يعرض السعر الذي يرجعه Google Play فعليًا، لذلك يجب إنشاء المنتجات بالأسعار أعلاه في Play Console بدل وضع السعر داخل التطبيق.

## 1) إنشاء المنتجات

في Play Console أنشئ ثلاثة منتجات One-time / Consumable باستخدام الـProduct IDs المذكورة أعلاه، واضبط سعر مصر كما هو في الجدول.

## 2) تفعيل Google Play Developer API

اربط حساب Play Console بمشروع Google Cloud، ثم أنشئ Service Account من API Access ومنحه صلاحيات الوصول إلى التطبيق. يجب أن يمتلك الحساب صلاحيات الفوترة/الطلبات اللازمة للتحقق من عمليات الشراء.

معرّف حزمة التطبيق الموجود في المشروع:

`com.example.tiktok_app`

## 3) Firebase Functions

الدالة الجديدة:

`verifyPlayPurchase`

تستقبل:
- `productId`
- `purchaseToken`

ثم تتحقق من Google Play قبل إضافة العملات. كل purchase token يُسجل مرة واحدة في:

`playPurchaseTransactions/{purchaseToken}`

وبذلك لا يمكن منح نفس عملية الشراء مرتين حتى لو وصل الطلب أكثر من مرة.

بعد تسجيل منح العملات، يقوم الخادم باستهلاك المنتج في Google Play حتى يستطيع المستخدم شراء نفس الباقة مرة أخرى.

## 4) قبل النشر

- ثبّت dependencies الخاصة بـFlutter وFirebase Functions.
- انشر Cloud Functions بعد ربط مشروع Firebase.
- أنشئ المنتجات في Play Console.
- أضف حساب اختبار License Tester.
- اختبر عملية شراء حقيقية في Internal testing/Closed testing قبل الإنتاج.

## ملاحظة مهمة

ملف المشروع المرفوع لا يحتوي على مجلد `android/`، لذلك تم تجهيز كود Billing في Dart وCloud Functions لكن لا يمكن بناء APK من هذه النسخة وحدها حتى تتم استعادة/إنشاء مشروع Android الخاص بـFlutter.
