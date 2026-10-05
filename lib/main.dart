import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

// Agora App ID الخاص بالبث المباشر
const agoraAppId = 'b959d814f9e04c70aa7c5d1808bb434f';
const int coinsPerEgp = 2; // 100 عملة = 50 جنيه
const int minimumWithdrawalEgp = 50;
const admobAppId = 'ca-app-pub-5663628720448893~5879440187';
const nativeFeedAdUnitId = 'ca-app-pub-5663628720448893/2486990081';
const testNativeFeedAdUnitId = 'ca-app-pub-3940256099942544/2247696110';
const firebaseStorageBucket = 'gs://st-video-app.firebasestorage.app';

FirebaseStorage get appStorage =>
    FirebaseStorage.instanceFor(bucket: firebaseStorageBucket);

// قائمة عالمية لحفظ الفيديوهات المنشورة ديناميكياً
class VideoItem {
  final String videoPath;
  final String caption;
  final String username;
  final bool commentsAllowed;
  final String selectedSong;
  final String downloadUrl;
  final String mediaType;

  VideoItem({
    required this.videoPath,
    required this.caption,
    required this.username,
    required this.commentsAllowed,
    required this.selectedSong,
    this.downloadUrl = '',
    this.mediaType = 'video',
  });
}

class AppData {
  static List<VideoItem> publishedVideos = [];
  static bool isLoggedIn = false;
  static String userEmail = 'saif_user@tiktok.com';
  static String userName = 'سيف المبرمج';
  static String userPhone = '+20 1000000000';
  static int userBalance = 1250;
  static List<CameraDescription> cameras = [];
  static String photoUrl = '';
  static String username = '';

  /// يحمّل الاسم والصورة المحفوظين من Firestore (مصدر الحقيقة الوحيد للملف الشخصي).
  static Future<void> loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    userEmail = user.email ?? userEmail;
    userName = user.displayName ?? user.email?.split('@').first ?? userName;
    photoUrl = user.photoURL ?? '';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final d = doc.data();
      if (d != null) {
        userName = (d['displayName'] as String?)?.trim().isNotEmpty == true
            ? d['displayName'] as String
            : userName;
        photoUrl = (d['photoUrl'] as String?) ?? photoUrl;
        username = (d['username'] as String?) ?? '';
        userPhone = (d['phone'] as String?) ?? '';
      }
    } catch (e) {
      debugPrint('loadProfile: $e');
    }
  }
}

// ======= خلفية متحركة + انتقالات 3D =======
class AppBackground extends StatefulWidget {
  const AppBackground({super.key});
  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _orb(Color color, double size, Alignment a) => Align(
        alignment: a,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              color.withValues(alpha: 0.45),
              color.withValues(alpha: 0)
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = Curves.easeInOut.transform(_c.value);
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF070A18),
                  Color(0xFF111A3B),
                  Color(0xFF210D2D)
                ],
              ),
            ),
            child: Stack(children: [
              _orb(const Color(0xFF00D9FF), 360,
                  Alignment(-1 + t * 0.8, -0.9 + t * 0.5)),
              _orb(const Color(0xFFFF167D), 400,
                  Alignment(1 - t * 0.8, 0.9 - t * 0.5)),
              _orb(const Color(0xFF7B2FF7), 300,
                  Alignment(0.8 - t * 1.4, -0.2 + t * 0.4)),
            ]),
          );
        },
      ),
    );
  }
}

/// انتقال ثلاثي الأبعاد (مكعب) بين الشاشات.
class Cube3DTransitionsBuilder extends PageTransitionsBuilder {
  const Cube3DTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      builder: (_, __) {
        final inV = 1 - Curves.easeOutCubic.transform(animation.value);
        final outV = Curves.easeInCubic.transform(secondaryAnimation.value);
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..translate(inV * MediaQuery.of(context).size.width * 0.5 -
              outV * MediaQuery.of(context).size.width * 0.25)
          ..rotateY(-inV * math.pi / 3 + outV * math.pi / 6);
        return Opacity(
          opacity: (1 - outV * 0.5).clamp(0.0, 1.0),
          child: Transform(
              transform: m, alignment: Alignment.center, child: child),
        );
      },
    );
  }
}

class Nav3D extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const Nav3D({super.key, required this.index, required this.onTap});

  static const _items = [
    (Icons.home_rounded, 'الرئيسية'),
    (Icons.explore_rounded, 'اكتشف'),
    (Icons.add_rounded, 'تصوير'),
    (Icons.notifications_rounded, 'الإشعارات'),
    (Icons.person_rounded, 'حسابي'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        height: 70,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: Colors.black.withValues(alpha: 0.55),
          border: Border.all(color: Colors.white24),
          boxShadow: const [
            BoxShadow(
                color: Color(0x5500D9FF), blurRadius: 24, offset: Offset(0, 6))
          ],
        ),
        child: Row(
          children: List.generate(_items.length, (i) {
            final selected = i == index;
            final isCenter = i == 2;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: selected ? 1 : 0),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutBack,
                  builder: (_, v, __) {
                    final m = Matrix4.identity()
                      ..setEntry(3, 2, 0.003)
                      ..rotateX(-0.35 * v)
                      ..translate(0.0, -8.0 * v, 20.0 * v);
                    return Transform(
                      alignment: Alignment.center,
                      transform: m,
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            isCenter
                                ? Container(
                                    width: 50,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(14),
                                      gradient: const LinearGradient(colors: [
                                        Color(0xFF00D9FF),
                                        Color(0xFFFF167D)
                                      ]),
                                      boxShadow: [
                                        BoxShadow(
                                            color: const Color(0xFFFF167D)
                                                .withValues(alpha: 0.5),
                                            blurRadius: 12)
                                      ],
                                    ),
                                    child: const Icon(Icons.add_rounded,
                                        color: Colors.white, size: 28),
                                  )
                                : Icon(_items[i].$1,
                                    size: 26 + 4 * v,
                                    color: Color.lerp(Colors.white54,
                                        const Color(0xFF00D9FF), v)),
                            if (!isCenter)
                              Text(_items[i].$2,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Color.lerp(
                                          Colors.white54, Colors.white, v))),
                          ]),
                    );
                  },
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await MobileAds.instance.initialize();
  AppData.isLoggedIn = FirebaseAuth.instance.currentUser != null;
  if (FirebaseAuth.instance.currentUser != null) {
    await AppData.loadProfile();
  }
  try {
    AppData.cameras = await availableCameras();
  } catch (e) {
    debugPrint("خطأ في تشغيل الكاميرات: $e");
  }
  runApp(const TikTokCloneApp());
}

class TikTokCloneApp extends StatelessWidget {
  const TikTokCloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TikTok Pro Clone',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: const Color(0xFF111A3B),
        primaryColor: Colors.redAccent,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: Colors.white.withValues(alpha: 0.08),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.08),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: Cube3DTransitionsBuilder(),
          TargetPlatform.iOS: Cube3DTransitionsBuilder(),
        }),
      ),
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [const AppBackground(), if (child != null) child],
      ),
      home: AppData.isLoggedIn ? const MainScreen() : const AuthScreen(),
    );
  }
}

// 1. شاشة المصادقة مع محاكاة فتح تطبيقات التواصل الخارجي
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;

  Future<void> _loginWithSocial(String providerName, Color themeColor) async {
    if (providerName != 'Google (Gmail)') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('تسجيل $providerName يحتاج إعداد OAuth الخاص به أولًا')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final account = await GoogleSignIn(
        serverClientId:
            '67126189193-akc65ebuqfnm9988212nbt47bqk061ul.apps.googleusercontent.com',
      ).signIn().timeout(const Duration(seconds: 30));
      if (account == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final auth =
          await account.authentication.timeout(const Duration(seconds: 20));
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      final result = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(const Duration(seconds: 30));
      final user = result.user!;
      if (!mounted) return;
      AppData.isLoggedIn = true;
      AppData.userEmail = user.email ?? '';
      AppData.userName =
          user.displayName ?? user.email?.split('@').first ?? 'مستخدم';
      Navigator.pushReplacement(
          context, MaterialPageRoute(builder: (_) => const MainScreen()));
      try {
        final ref =
            FirebaseFirestore.instance.collection('users').doc(user.uid);
        final snap = await ref.get().timeout(const Duration(seconds: 10));
        final data = <String, dynamic>{
          'uid': user.uid,
          'email': user.email,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        // أول دخول فقط: لا نكتب فوق الاسم/الصورة المعدلة.
        if (!snap.exists || snap.data()?['displayName'] == null) {
          data['displayName'] = user.displayName ?? 'مستخدم جديد';
        }
        if (!snap.exists || snap.data()?['photoUrl'] == null) {
          data['photoUrl'] = user.photoURL;
        }
        await ref
            .set(data, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
        await AppData.loadProfile();
      } catch (_) {
        // دخول Google تم بنجاح؛ فشل حفظ الملف الشخصي لا يمنع فتح التطبيق.
      }
    } on FirebaseAuthException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('فشل Google: ${e.message ?? e.code}')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل تسجيل Google: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitAuthForm() async {
    final identifier = _emailController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    if (identifier.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'أدخل البريد أو اسم المستخدم وكلمة مرور من 6 أحرف على الأقل')));
      return;
    }
    if (!_isLogin && (username.length < 3 || !identifier.contains('@'))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('أدخل اسم مستخدم من 3 أحرف وبريدًا إلكترونيًا صحيحًا')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      var email = identifier;
      if (_isLogin && !identifier.contains('@')) {
        final nameDoc = await FirebaseFirestore.instance
            .collection('usernames')
            .doc(identifier.toLowerCase())
            .get();
        if (!nameDoc.exists) {
          throw FirebaseAuthException(
              code: 'user-not-found', message: 'اسم المستخدم غير موجود');
        }
        email = nameDoc.data()?['email'] as String? ?? '';
        if (email.isEmpty) {
          throw FirebaseAuthException(
              code: 'invalid-user-data', message: 'بيانات المستخدم غير مكتملة');
        }
      }
      if (!_isLogin) {
        final existing = await FirebaseFirestore.instance
            .collection('usernames')
            .doc(username)
            .get();
        if (existing.exists) {
          throw FirebaseAuthException(
              code: 'username-already-in-use',
              message: 'اسم المستخدم مستخدم بالفعل');
        }
      }
      final result = _isLogin
          ? await FirebaseAuth.instance
              .signInWithEmailAndPassword(email: email, password: password)
          : await FirebaseAuth.instance
              .createUserWithEmailAndPassword(email: email, password: password);
      final user = result.user!;
      if (!_isLogin) {
        try {
          await user.updateDisplayName(username);
        } catch (_) {}
      }
      AppData.isLoggedIn = true;
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final existingProfile = await userRef.get();
      final userData = <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      // لا نكتب فوق الاسم المعدل: نضبط الاسم فقط عند إنشاء الحساب أو لو مفيش اسم محفوظ.
      if (!existingProfile.exists ||
          existingProfile.data()?['displayName'] == null) {
        userData['displayName'] =
            _isLogin ? user.displayName ?? email.split('@').first : username;
      }
      if (!_isLogin) {
        userData['username'] = username;
        try {
          await FirebaseFirestore.instance
              .collection('usernames')
              .doc(username)
              .set({'uid': user.uid, 'email': user.email});
        } catch (_) {}
      }
      await userRef.set(userData, SetOptions(merge: true));
      await AppData.loadProfile();
      if (mounted)
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'user-not-found' => 'اسم المستخدم أو البريد غير موجود',
        'wrong-password' ||
        'invalid-credential' =>
          'اسم المستخدم أو كلمة المرور غير صحيحة',
        'email-already-in-use' => 'هذا البريد مستخدم بالفعل',
        'username-already-in-use' => 'اسم المستخدم مستخدم بالفعل',
        'operation-not-allowed' => 'فعّل Email/Password من Firebase Console',
        _ => e.message ?? 'فشل تسجيل الدخول',
      };
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF070A18), Color(0xFF111A3B), Color(0xFF210D2D)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -120,
              right: -90,
              child: _glowOrb(const Color(0xFF00D9FF), 280),
            ),
            Positioned(
              bottom: -130,
              left: -100,
              child: _glowOrb(const Color(0xFFFF167D), 300),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.08),
                          border: Border.all(color: Colors.white24),
                          boxShadow: const [
                            BoxShadow(
                                color: Color(0x6600D9FF),
                                blurRadius: 28,
                                spreadRadius: 2),
                          ],
                        ),
                        child: const Icon(Icons.music_video,
                            size: 58, color: Colors.white),
                      ),
                      const SizedBox(height: 20),
                      Text(
                          _isLogin
                              ? 'تسجيل الدخول لتيك توك'
                              : 'إنشاء حساب جديد 🚀',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 30),
                      if (!_isLogin)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 15),
                          child: TextField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                                hintText: 'اسم المستخدم',
                                filled: true,
                                prefixIcon: Icon(Icons.person)),
                          ),
                        ),
                      TextField(
                        controller: _emailController,
                        keyboardType: _isLogin
                            ? TextInputType.text
                            : TextInputType.emailAddress,
                        decoration: InputDecoration(
                          hintText: _isLogin
                              ? 'البريد الإلكتروني أو اسم المستخدم'
                              : 'البريد الإلكتروني',
                          filled: true,
                          prefixIcon: const Icon(Icons.email),
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                              hintText: 'كلمة المرور', filled: true)),
                      const SizedBox(height: 25),
                      _isLoading
                          ? const CircularProgressIndicator(
                              color: Colors.redAccent)
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.redAccent,
                                  minimumSize: const Size(double.infinity, 50)),
                              onPressed: _submitAuthForm,
                              child: Text(_isLogin ? 'دخول' : 'تسجيل',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 16)),
                            ),
                      TextButton(
                        onPressed: () => setState(() => _isLogin = !_isLogin),
                        child: Text(
                            _isLogin
                                ? 'ليس لديك حساب؟ أنشئ حساباً'
                                : 'لديك حساب؟ سجل دخولك',
                            style: const TextStyle(color: Colors.amber)),
                      ),
                      const Divider(height: 30, color: Colors.white24),
                      const Text('أو المتابعة باستخدام',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 13)),
                      const SizedBox(height: 15),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.g_mobiledata,
                            size: 34, color: Colors.white),
                        label: const Text('تسجيل الدخول باستخدام Google',
                            style: TextStyle(color: Colors.white)),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          side: const BorderSide(color: Colors.white38),
                          backgroundColor: Colors.white10,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _isLoading
                            ? null
                            : () => _loginWithSocial(
                                'Google (Gmail)', Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glowOrb(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: color.withValues(alpha: 0.20),
                blurRadius: 110,
                spreadRadius: 35)
          ],
        ),
      ),
    );
  }
}

// 2. الشاشة الرئيسية والتنقل السفلي
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  int _dir = 1;

  Widget _screenFor(int i) {
    switch (i) {
      case 0:
        return const VideoFeedScreen(key: ValueKey(0));
      case 1:
        return const DiscoverScreen(key: ValueKey(1));
      case 2:
        return const CameraStudioScreen(key: ValueKey(2));
      case 3:
        return const InboxScreen(key: ValueKey(3));
      default:
        return const ProfileScreen(key: ValueKey(4));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        transitionBuilder: (child, anim) {
          final isIn = child.key == ValueKey(_currentIndex);
          final sign = isIn ? _dir : -_dir;
          return AnimatedBuilder(
            animation: anim,
            child: child,
            builder: (_, c) {
              final v = 1 - anim.value;
              final m = Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(sign * v * math.pi / 2.2);
              return Transform(
                transform: m,
                alignment: (isIn == (_dir > 0))
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Opacity(opacity: anim.value.clamp(0.0, 1.0), child: c),
              );
            },
          );
        },
        child: _screenFor(_currentIndex),
      ),
      bottomNavigationBar: Nav3D(
        index: _currentIndex,
        onTap: (i) {
          if (i == _currentIndex) return;
          setState(() {
            _dir = i > _currentIndex ? 1 : -1;
            _currentIndex = i;
          });
        },
      ),
    );
  }
}

const Map<String, List<double>> kVideoFilters = {
  'none': [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0],
  'warm': [1.15, 0, 0, 0, 12, 0, 1.0, 0, 0, 0, 0, 0, 0.85, 0, 0, 0, 0, 0, 1, 0],
  'cool': [0.85, 0, 0, 0, 0, 0, 1.0, 0, 0, 0, 0, 0, 1.2, 0, 14, 0, 0, 0, 1, 0],
  'bw': [
    0.33,
    0.59,
    0.11,
    0,
    0,
    0.33,
    0.59,
    0.11,
    0,
    0,
    0.33,
    0.59,
    0.11,
    0,
    0,
    0,
    0,
    0,
    1,
    0
  ],
  'vivid': [
    1.3,
    -0.1,
    -0.1,
    0,
    0,
    -0.1,
    1.3,
    -0.1,
    0,
    0,
    -0.1,
    -0.1,
    1.3,
    0,
    0,
    0,
    0,
    0,
    1,
    0
  ],
  'vintage': [
    0.9,
    0.3,
    0.1,
    0,
    0,
    0.2,
    0.8,
    0.1,
    0,
    0,
    0.15,
    0.25,
    0.6,
    0,
    0,
    0,
    0,
    0,
    1,
    0
  ],
};
const Map<String, String> kFilterLabels = {
  'none': 'أصلي',
  'warm': 'دافئ',
  'cool': 'بارد',
  'bw': 'أبيض وأسود',
  'vivid': 'حيوي',
  'vintage': 'قديم',
};

Widget applyFilter(String filter, Widget child) {
  final m = kVideoFilters[filter];
  if (m == null || filter == 'none') return child;
  return ColorFiltered(colorFilter: ColorFilter.matrix(m), child: child);
}

/// كتالوج الموسيقى (روابط مباشرة تعمل بدون مفاتيح). عدّل القائمة لإضافة أغانيك.
class Song {
  final String title;
  final String url;
  const Song(this.title, this.url);
}

const String _sh = 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-';
const List<Song> kSongs = [
  Song('بدون موسيقى', ''),
  Song('أغنية الحماس والترند 🎵', '${_sh}1.mp3'),
  Song('ريمكس رقصة تيك توك 🔥', '${_sh}8.mp3'),
  Song('موسيقى هادئة ورومانسية 🎸', '${_sh}3.mp3'),
  Song('إيقاع سريع ورائع ⚡', '${_sh}6.mp3'),
  Song('بيت إلكتروني 🎧', '${_sh}11.mp3'),
  Song('لو فاي للاسترخاء 🌙', '${_sh}14.mp3'),
];

String songUrlFor(String title) =>
    kSongs.firstWhere((s) => s.title == title, orElse: () => kSongs.first).url;

/// يشغل موسيقى خلفية (بدون واجهة) ويتوقف عند عدم النشاط.
class BgMusic extends StatefulWidget {
  final String url;
  final double volume;
  final bool active;
  const BgMusic(
      {super.key, required this.url, this.volume = 0.5, this.active = true});
  @override
  State<BgMusic> createState() => _BgMusicState();
}

class _BgMusicState extends State<BgMusic> {
  final AudioPlayer _player = AudioPlayer();

  Future<void> _sync({bool urlChanged = false}) async {
    try {
      if (widget.url.isEmpty || !widget.active) {
        await _player.pause();
        return;
      }
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(widget.volume.clamp(0.0, 1.0));
      if (urlChanged || _player.state != PlayerState.playing) {
        await _player.play(UrlSource(widget.url));
      }
    } catch (e) {
      debugPrint('music error: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _sync(urlChanged: true);
  }

  @override
  void didUpdateWidget(covariant BgMusic old) {
    super.didUpdateWidget(old);
    _sync(urlChanged: old.url != widget.url);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// مشغل فيديو (شبكة أو ملف محلي) يدعم التشغيل التلقائي، التكرار، القص، الفلتر ومستوى الصوت.
class RemoteVideo extends StatefulWidget {
  final String url;
  final String? filePath;
  final bool active;
  final int trimStartMs;
  final int trimEndMs; // 0 = حتى النهاية
  final String filter;
  final double volume;
  final ValueChanged<Duration>? onDuration;
  const RemoteVideo({
    super.key,
    this.url = '',
    this.filePath,
    this.active = true,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.filter = 'none',
    this.volume = 1.0,
    this.onDuration,
  });
  @override
  State<RemoteVideo> createState() => _RemoteVideoState();
}

class _RemoteVideoState extends State<RemoteVideo> {
  late final VideoPlayerController _controller;
  bool _failed = false;

  void _tick() {
    final v = _controller.value;
    if (!v.isInitialized || !v.isPlaying) return;
    final end =
        widget.trimEndMs > 0 ? widget.trimEndMs : v.duration.inMilliseconds;
    if (v.position.inMilliseconds >= end - 80) {
      _controller.seekTo(Duration(milliseconds: widget.trimStartMs));
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.filePath != null
        ? VideoPlayerController.file(File(widget.filePath!))
        : VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller.initialize().then((_) async {
      if (!mounted) return;
      await _controller.setLooping(true);
      await _controller.setVolume(widget.volume);
      if (widget.trimStartMs > 0)
        await _controller.seekTo(Duration(milliseconds: widget.trimStartMs));
      widget.onDuration?.call(_controller.value.duration);
      _controller.addListener(_tick);
      if (widget.active) await _controller.play();
      if (mounted) setState(() {});
    }).catchError((e) {
      debugPrint('video init error: $e');
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  void didUpdateWidget(covariant RemoteVideo old) {
    super.didUpdateWidget(old);
    if (!_controller.value.isInitialized) return;
    if (old.volume != widget.volume) _controller.setVolume(widget.volume);
    if (old.trimStartMs != widget.trimStartMs) {
      _controller.seekTo(Duration(milliseconds: widget.trimStartMs));
    }
    if (old.active != widget.active) {
      widget.active ? _controller.play() : _controller.pause();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_tick);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed)
      return const Center(
          child: Icon(Icons.error_outline, size: 48, color: Colors.white54));
    if (!_controller.value.isInitialized)
      return const Center(child: CircularProgressIndicator());
    return GestureDetector(
      onTap: () {
        setState(() {
          _controller.value.isPlaying
              ? _controller.pause()
              : _controller.play();
        });
      },
      child: applyFilter(
        widget.filter,
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          ),
        ),
      ),
    );
  }
}

class NativeFeedAd extends StatefulWidget {
  const NativeFeedAd({super.key});

  @override
  State<NativeFeedAd> createState() => _NativeFeedAdState();
}

class _NativeFeedAdState extends State<NativeFeedAd> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final ad = NativeAd(
      adUnitId: kReleaseMode ? nativeFeedAdUnitId : testNativeFeedAdUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFF171717),
        cornerRadius: 12,
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _ad = ad as NativeAd;
            _loaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Native Ad failed to load: $error');
          ad.dispose();
        },
      ),
    );
    _ad = ad;
    ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) {
      return const Center(
          child: Text('إعلان', style: TextStyle(color: Colors.white54)));
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('إعلان',
                style: TextStyle(color: Colors.white60, fontSize: 12)),
          ),
          Expanded(child: AdWidget(ad: _ad!)),
        ],
      ),
    );
  }
}

// 3. شاشة الفيديوهات الرئيسية المرتبطة بـ Firestore
class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final TextEditingController _searchController = TextEditingController();
  int _page = 0;

  Future<void> _toggleLike(String videoId, bool wasLiked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final videoRef =
        FirebaseFirestore.instance.collection('videos').doc(videoId);
    final likeRef = videoRef.collection('likes').doc(user.uid);
    String? ownerId;
    bool didLike = false;
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(videoRef);
      final likeSnapshot = await transaction.get(likeRef);
      if (!snapshot.exists) throw StateError('المنشور غير موجود');
      ownerId = snapshot.data()?['ownerId'] as String?;
      final current = (snapshot.data()?['likesCount'] as num? ?? 0).toInt();
      didLike = !likeSnapshot.exists;
      if (didLike) {
        transaction.set(likeRef,
            {'userId': user.uid, 'createdAt': FieldValue.serverTimestamp()});
        transaction.update(videoRef, {'likesCount': current + 1});
      } else {
        transaction.delete(likeRef);
        transaction.update(videoRef,
            {'likesCount': current > 0 ? current - 1 : 0});
      }
    });
    if (didLike && ownerId != null && ownerId != user.uid) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('notifications')
            .add({
          'title': 'إعجاب جديد',
          'body': '${AppData.userName} أعجب بمنشورك',
          'type': 'like',
          'actorId': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('like notification: $e');
      }
    }
  }

  Future<void> _addComment(String videoId, String text) async {
    final user = FirebaseAuth.instance.currentUser;
    final value = text.trim();
    if (user == null || value.isEmpty) return;
    final videoRef =
        FirebaseFirestore.instance.collection('videos').doc(videoId);
    final commentRef = videoRef.collection('comments').doc();
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(videoRef);
      final current = (snapshot.data()?['commentsCount'] as num? ?? 0).toInt();
      transaction.set(commentRef, {
        'userId': user.uid,
        'username': AppData.userName,
        'text': value,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(videoRef, {'commentsCount': current + 1});
    });
    try {
      final ownerId = (await videoRef.get()).data()?['ownerId'];
      if (ownerId != null && ownerId != user.uid) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('notifications')
            .add({
          'title': 'تعليق جديد',
          'body': '${AppData.userName} كتب تعليقًا على منشورك',
          'type': 'comment',
          'actorId': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('comment notification: $e');
    }
  }

  void _showCommentsSheet(String videoId, bool allowed) {
    if (!allowed) {
      showModalBottomSheet(
        context: context,
        builder: (_) => const SizedBox(
            height: 180,
            child: Center(child: Text('التعليقات مغلقة لهذا المنشور'))),
      );
      return;
    }
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .65,
          child: Column(children: [
            const Padding(
                padding: EdgeInsets.all(14),
                child: Text('التعليقات',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('videos')
                    .doc(videoId)
                    .collection('comments')
                    .orderBy('createdAt', descending: true)
                    .snapshots(),
                builder: (_, snapshot) {
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  if (snapshot.data!.docs.isEmpty)
                    return const Center(child: Text('كن أول من يعلق'));
                  return ListView(
                    children: snapshot.data!.docs.map((doc) {
                      final data = doc.data();
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(data['username'] ?? 'مستخدم'),
                        subtitle: Text(data['text'] ?? ''),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
            Row(children: [
              Expanded(
                  child: TextField(
                      controller: controller,
                      decoration:
                          const InputDecoration(hintText: 'اكتب تعليقًا...'))),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.redAccent),
                onPressed: () async {
                  await _addComment(videoId, controller.text);
                  controller.clear();
                },
              ),
            ]),
          ]),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('videos')
        .orderBy('createdAt', descending: true);
    return Scaffold(
      body: Stack(children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return Center(
                  child: Text('خطأ في تحميل المنشورات: ${snapshot.error}'));
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final term = _searchController.text.trim().toLowerCase();
            final docs = snapshot.data!.docs.where((doc) {
              if (term.isEmpty) return true;
              final data = doc.data();
              return '${data['caption'] ?? ''} ${data['username'] ?? ''}'
                  .toLowerCase()
                  .contains(term);
            }).toList();
            if (docs.isEmpty)
              return const Center(child: Text('لا توجد منشورات مطابقة'));
            // قائمة العناصر: فيديو، وبعد كل 4 فيديوهات إعلان (null = إعلان)
            final entries = <int?>[];
            for (var i = 0; i < docs.length; i++) {
              entries.add(i);
              if ((i + 1) % 4 == 0) entries.add(null);
            }
            return PageView.builder(
              scrollDirection: Axis.vertical,
              itemCount: entries.length,
              onPageChanged: (p) => setState(() => _page = p),
              itemBuilder: (_, index) {
                final videoIndex = entries[index];
                if (videoIndex == null) return const NativeFeedAd();
                return FirestoreVideoCard(
                  key: ValueKey(docs[videoIndex].id),
                  doc: docs[videoIndex],
                  active: index == _page,
                  onComment: _showCommentsSheet,
                  onLike: _toggleLike,
                );
              },
            );
          },
        ),
        Positioned(
          top: 40,
          left: 16,
          right: 16,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'ابحث عن مستخدمين أو هاشتاجات...',
              filled: true,
              fillColor: Colors.black54,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
      ]),
    );
  }
}

class PublicProfileScreen extends StatefulWidget {
  final String userId;
  final String username;
  const PublicProfileScreen(
      {super.key, required this.userId, required this.username});
  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool _following = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadFollowing();
  }

  Future<void> _loadFollowing() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(me.uid)
        .collection('following')
        .doc(widget.userId)
        .get();
    if (mounted) setState(() => _following = doc.exists);
  }

  Future<void> _toggleFollow() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || me.uid == widget.userId) return;
    setState(() => _busy = true);
    try {
      final db = FirebaseFirestore.instance;
      final following = db
          .collection('users')
          .doc(me.uid)
          .collection('following')
          .doc(widget.userId);
      final follower = db
          .collection('users')
          .doc(widget.userId)
          .collection('followers')
          .doc(me.uid);
      final myRef = db.collection('users').doc(me.uid);
      final targetRef = db.collection('users').doc(widget.userId);
      await db.runTransaction((tx) async {
      final target = await tx.get(targetRef);
      final mine = await tx.get(myRef);
      final followers = (target.data()?['followersCount'] as num? ?? 0).toInt();
      final followingCount =
          (mine.data()?['followingCount'] as num? ?? 0).toInt();
      if (_following) {
        tx.delete(following);
        tx.delete(follower);
        tx.update(
            targetRef, {'followersCount': followers > 0 ? followers - 1 : 0});
        tx.update(myRef,
            {'followingCount': followingCount > 0 ? followingCount - 1 : 0});
      } else {
        tx.set(following, {
          'userId': widget.userId,
          'createdAt': FieldValue.serverTimestamp()
        });
        tx.set(follower,
            {'userId': me.uid, 'createdAt': FieldValue.serverTimestamp()});
        tx.update(targetRef, {'followersCount': followers + 1});
        tx.update(myRef, {'followingCount': followingCount + 1});
      }
      });
      if (!_following) {
        await db
            .collection('users')
            .doc(widget.userId)
            .collection('notifications')
            .add({
          'title': 'متابع جديد',
          'body': '${AppData.userName} بدأ متابعتك',
          'type': 'follow',
          'actorId': me.uid,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      if (mounted) setState(() => _following = !_following);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر تحديث المتابعة: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final videos = FirebaseFirestore.instance
        .collection('videos')
        .where('ownerId', isEqualTo: widget.userId)
        .snapshots();
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.username}')),
      body: Column(children: [
        const SizedBox(height: 20),
        Text('@${widget.username}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        FilledButton(
          onPressed: _busy ? null : _toggleFollow,
          child: Text(_following ? 'إلغاء المتابعة' : 'متابعة'),
        ),
        const Divider(),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: videos,
            builder: (_, snap) {
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              return GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: snap.data!.docs.length,
                itemBuilder: (_, i) =>
                    MediaThumb(data: snap.data!.docs[i].data()),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class FirestoreVideoCard extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final void Function(String, bool) onComment;
  final Future<void> Function(String, bool) onLike;
  final bool active;
  const FirestoreVideoCard(
      {super.key,
      required this.doc,
      required this.onComment,
      required this.onLike,
      this.active = true});
  @override
  State<FirestoreVideoCard> createState() => _FirestoreVideoCardState();
}

class _FirestoreVideoCardState extends State<FirestoreVideoCard> {
  bool _liked = false;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _loadLike();
    _loadSaved();
  }

  Future<void> _loadLike() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await widget.doc.reference.collection('likes').doc(uid).get();
    if (mounted) setState(() => _liked = snap.exists);
  }

  Future<void> _loadSaved() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('savedVideos')
        .doc(widget.doc.id)
        .get();
    if (mounted) setState(() => _saved = snap.exists);
  }

  Future<void> _toggleSaved() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('savedVideos')
        .doc(widget.doc.id);
    if (_saved) {
      await ref.delete();
    } else {
      await ref.set({
        'videoId': widget.doc.id,
        'createdAt': FieldValue.serverTimestamp()
      });
    }
    if (mounted) setState(() => _saved = !_saved);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final url = data['downloadUrl'] as String? ?? '';
    final isImage = data['mediaType'] == 'image';
    final likes = (data['likesCount'] as num? ?? 0).toInt();
    final comments = (data['commentsCount'] as num? ?? 0).toInt();
    return Stack(fit: StackFit.expand, children: [
      if (url.isEmpty)
        const ColoredBox(
            color: Colors.black,
            child: Center(child: Icon(Icons.play_circle, size: 80)))
      else if (isImage)
        applyFilter(data['filter'] as String? ?? 'none',
            Image.network(url, fit: BoxFit.cover))
      else
        RemoteVideo(
          url: url,
          active: widget.active,
          trimStartMs: (data['trimStartMs'] as num? ?? 0).toInt(),
          trimEndMs: (data['trimEndMs'] as num? ?? 0).toInt(),
          filter: data['filter'] as String? ?? 'none',
          volume: (data['originalVolume'] as num? ?? 1.0).toDouble(),
        ),
      BgMusic(
        url: data['musicUrl'] as String? ?? '',
        volume: (data['musicVolume'] as num? ?? 0.5).toDouble(),
        active: widget.active,
      ),
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black87],
          ),
        ),
      ),
      Positioned(
        left: 15,
        right: 90,
        bottom: 110,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PublicProfileScreen(
                  userId: data['ownerId'] ?? '',
                  username: data['username'] ?? 'user',
                ),
              ),
            ),
            child: Text('@${data['username'] ?? 'user'}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 5),
          Text(data['caption'] ?? ''),
          const SizedBox(height: 5),
          Text('♫ ${data['selectedSong'] ?? ''}',
              style: const TextStyle(fontSize: 12)),
        ]),
      ),
      Positioned(
        right: 10,
        bottom: 100,
        child: Column(children: [
          IconButton(
            icon: Icon(_liked ? Icons.favorite : Icons.favorite_border,
                color: _liked ? Colors.red : Colors.white, size: 38),
            onPressed: () async {
              final was = _liked;
              setState(() => _liked = !was);
              try {
                await widget.onLike(widget.doc.id, was);
              } catch (e) {
                if (mounted) {
                  setState(() => _liked = was);
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('تعذر تسجيل الإعجاب: $e')));
                }
              }
            },
          ),
          Text('$likes'),
          const SizedBox(height: 12),
          IconButton(
            icon: const Icon(Icons.comment, size: 34),
            onPressed: () => widget.onComment(
                widget.doc.id, data['commentsAllowed'] != false),
          ),
          Text('$comments'),
          const SizedBox(height: 12),
          IconButton(
            icon: const Icon(Icons.share, size: 34),
            tooltip: 'مشاركة الفيديو',
            onPressed: () async {
              final caption = (data['caption'] as String? ?? '').trim();
              final shareText = caption.isEmpty
                  ? 'شاهد هذا الفيديو على ST Video'
                  : '$caption\nشاهد هذا الفيديو على ST Video';
              await Share.share('$shareText\n$url');
            },
          ),
          const Text('مشاركة', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          IconButton(
            onPressed: _toggleSaved,
            icon:
                Icon(_saved ? Icons.bookmark : Icons.bookmark_border, size: 32),
          ),
          const Text('حفظ', style: TextStyle(fontSize: 12)),
        ]),
      ),
    ]);
  }
}

// 4. استوديو التصوير الحقيقي (كاميرا + صورة وفيديو وبث مباشر + معرض + أغاني وتحكم بالصوت)
class CameraStudioScreen extends StatefulWidget {
  const CameraStudioScreen({super.key});

  @override
  State<CameraStudioScreen> createState() => _CameraStudioScreenState();
}

class _CameraStudioScreenState extends State<CameraStudioScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  String _selectedMode = 'فيديو'; // (صورة، فيديو، بث مباشر)
  String _selectedFilter = 'بدون فلتر';
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (AppData.cameras.isEmpty) return;

    final controller = CameraController(
      AppData.cameras.first,
      ResolutionPreset.high,
      enableAudio: true,
    );
    _controller = controller;

    try {
      await controller.initialize();
      if (mounted) setState(() => _isCameraInitialized = true);
    } on CameraException catch (e) {
      debugPrint('خطأ فتح الكاميرا: ${e.code}');
      await controller.dispose();
      _controller = null;
    }
  }

  // نقفل الكاميرا قبل فتح البث عشان Agora يقدر يستخدمها، وبعدين نفتحها تاني
  Future<void> _openLiveStream() async {
    final old = _controller;
    _controller = null;
    if (mounted) setState(() => _isCameraInitialized = false);
    await old?.dispose();
    if (!mounted) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (context) => const LiveStreamScreen()));
    if (mounted) _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final XFile? pickedFile = _selectedMode == 'صورة'
        ? await picker.pickImage(source: ImageSource.gallery)
        : await picker.pickVideo(source: ImageSource.gallery);

    if (!mounted || pickedFile == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UploadPostScreen(
            mediaPath: pickedFile.path, isImage: _selectedMode == 'صورة'),
      ),
    );
  }

  Future<void> _openSnapCameraKit() async {
    // Camera Kit runs native Android code and a failure there can terminate the
    // process before Dart receives a PlatformException. Use the built-in camera
    // as a safe fallback instead of allowing the app to crash.
    final statuses =
        await [Permission.camera, Permission.microphone].request();
    if (statuses[Permission.camera]?.isGranted != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('اسمح للتطبيق بالكاميرا من إعدادات الهاتف أولًا')));
      }
      return;
    }
    final old = _controller;
    _controller = null;
    if (mounted) setState(() => _isCameraInitialized = false);
    await old?.dispose();
    try {
      final captured = await ImagePicker().pickVideo(source: ImageSource.camera);
      if (!mounted || captured == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => UploadPostScreen(mediaPath: captured.path)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('تعذر فتح الكاميرا: $e')));
      }
    } finally {
      if (mounted) await _initCamera();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('الكاميرا الحية')),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ElevatedButton.icon(
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              icon: const Icon(Icons.video_library),
              label: const Text('اختر فيديو من المعرض'),
              onPressed: () {
                setState(() => _selectedMode = 'فيديو');
                _pickFromGallery();
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
              icon: const Icon(Icons.photo_library),
              label: const Text('اختر صورة من المعرض'),
              onPressed: () {
                setState(() => _selectedMode = 'صورة');
                _pickFromGallery();
              },
            ),
          ]),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),
          Container(
            color: _selectedFilter == 'فلتر نيون أزرق'
                ? Colors.blue.withOpacity(0.15)
                : _selectedFilter == 'فلتر جمالي دافئ'
                    ? Colors.orange.withOpacity(0.15)
                    : Colors.transparent,
          ),
          // أزرار الفلاتر الجانبية
          Positioned(
            top: 50,
            right: 16,
            child: Column(
              children: [
                IconButton(
                  icon: const Icon(Icons.face, color: Colors.white, size: 32),
                  onPressed: () {
                    setState(() {
                      _selectedFilter = _selectedFilter == 'فلتر جمالي دافئ'
                          ? 'فلتر نيون أزرق'
                          : 'فلتر جمالي دافئ';
                    });
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('تم تفعيل: $_selectedFilter ✨')));
                  },
                ),
                const Text('كاميرا آمنة',
                    style: TextStyle(color: Colors.white, fontSize: 10)),
                const SizedBox(height: 18),
                IconButton(
                  icon: const Icon(Icons.auto_awesome,
                      color: Colors.amber, size: 32),
                  onPressed: _openSnapCameraKit,
                  tooltip: 'فتح الكاميرا الآمنة',
                ),
                const Text('تصوير آمن',
                    style: TextStyle(color: Colors.white, fontSize: 10)),
              ],
            ),
          ),
          // زر التقاط الصورة / الفيديو / البث السفلي مع خيار المعرض والوضع
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // التبديل بين الأوضاع (صورة، فيديو، بث مباشر)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: ['صورة', 'فيديو', 'بث مباشر'].map((mode) {
                    final isSelected = _selectedMode == mode;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedMode = mode),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          mode,
                          style: TextStyle(
                            color: isSelected ? Colors.amber : Colors.white,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // خانة المعرض بجانب زر التصوير
                    IconButton(
                      icon: const Icon(Icons.photo_library,
                          color: Colors.white, size: 36),
                      onPressed: _pickFromGallery,
                      tooltip: 'اختر من المعرض',
                    ),
                    // زر الالتقاط الأساسي
                    GestureDetector(
                      onTap: () async {
                        if (_selectedMode == 'بث مباشر') {
                          await _openLiveStream();
                          return;
                        }
                        if (_selectedMode == 'صورة') {
                          final image = await _controller!.takePicture();
                          if (mounted) {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) => UploadPostScreen(
                                        mediaPath: image.path, isImage: true)));
                          }
                        } else {
                          try {
                            if (_isRecording) {
                              final file =
                                  await _controller!.stopVideoRecording();
                              setState(() => _isRecording = false);
                              if (mounted) {
                                Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) => UploadPostScreen(
                                            mediaPath: file.path)));
                              }
                            } else {
                              await _controller!.startVideoRecording();
                              setState(() => _isRecording = true);
                            }
                          } catch (e) {
                            final picker = ImagePicker();
                            final picked = await picker.pickVideo(
                                source: ImageSource.camera);
                            if (picked != null && mounted) {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) => UploadPostScreen(
                                          mediaPath: picked.path)));
                            }
                          }
                        }
                      },
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: _isRecording ? Colors.red : Colors.redAccent,
                        ),
                        child: Center(
                          child: Icon(
                            _selectedMode == 'بث مباشر'
                                ? Icons.live_tv
                                : _selectedMode == 'صورة'
                                    ? Icons.camera
                                    : (_isRecording
                                        ? Icons.stop
                                        : Icons.fiber_manual_record),
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 36), // توازن الـ Row
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// شاشة معاينة الفيديو/الصورة قبل النشر مع خانة الأغاني والتحكم في مستويات الصوت
class UploadPostScreen extends StatefulWidget {
  final String mediaPath;
  final bool? isImage;
  const UploadPostScreen({super.key, required this.mediaPath, this.isImage});

  @override
  State<UploadPostScreen> createState() => _UploadPostScreenState();
}

class _UploadPostScreenState extends State<UploadPostScreen> {
  final TextEditingController _captionController = TextEditingController();
  bool _commentsAllowed = true;
  String _selectedSong =
      'أغنية الحماس والترند 🎵'; // أغنية افتراضية تليق بالصورة/الفيديو تلقائياً
  double _originalSoundVolume = 0.8;
  double _addedSongVolume = 0.5;
  // التعديل قبل النشر
  String _filter = 'none';
  Duration _duration = Duration.zero;
  RangeValues _trim = const RangeValues(0, 1); // نسبة من مدة الفيديو
  bool _uploading = false;
  double _progress = 0;

  bool get _isImage {
    if (widget.isImage != null) return widget.isImage!;
    final p = widget.mediaPath.toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.webp', '.heic', '.gif'].any(p.endsWith);
  }

  int get _trimStartMs => (_duration.inMilliseconds * _trim.start).round();
  int get _trimEndMs =>
      _trim.end >= 0.999 ? 0 : (_duration.inMilliseconds * _trim.end).round();

  void _insertText(String textToInsert) {
    final currentText = _captionController.text;
    final selection = _captionController.selection;
    if (selection.start >= 0) {
      final newText = currentText.replaceRange(
          selection.start, selection.end, textToInsert);
      _captionController.text = newText;
      _captionController.selection = TextSelection.collapsed(
          offset: selection.start + textToInsert.length);
    } else {
      _captionController.text = '$currentText $textToInsert';
    }
  }

  void _openSongsPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final availableSongs = kSongs.map((e) => e.title).toList();
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('اختر الأغنية أو الموسيقى',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 200,
                    child: ListView.builder(
                      itemCount: availableSongs.length,
                      itemBuilder: (context, index) {
                        final song = availableSongs[index];
                        return ListTile(
                          title: Text(song,
                              style: const TextStyle(color: Colors.white)),
                          trailing: _selectedSong == song
                              ? const Icon(Icons.check, color: Colors.amber)
                              : null,
                          onTap: () {
                            setState(() => _selectedSong = song);
                            setModalState(() {});
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(color: Colors.grey),
                  const Text('التحكم في مستويات الصوت 🎚️',
                      style: TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Text('الصوت الأصلي',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _originalSoundVolume,
                          min: 0,
                          max: 1,
                          activeColor: Colors.redAccent,
                          onChanged: (val) {
                            setState(() => _originalSoundVolume = val);
                            setModalState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('الصوت المضاف',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _addedSongVolume,
                          min: 0,
                          max: 1,
                          activeColor: Colors.amber,
                          onChanged: (val) {
                            setState(() => _addedSongVolume = val);
                            setModalState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _publishVideo() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('سجل الدخول أولًا')));
      return;
    }
    if (_uploading) return;
    setState(() {
      _uploading = true;
      _progress = 0;
    });
    try {
      final file = File(widget.mediaPath);
      if (!await file.exists()) throw Exception('الملف غير موجود');
      final id = FirebaseFirestore.instance.collection('videos').doc().id;
      final isImage = _isImage;
      final lower = widget.mediaPath.toLowerCase();
      final ext = isImage ? (lower.endsWith('.png') ? 'png' : 'jpg') : 'mp4';
      final contentType =
          isImage ? (ext == 'png' ? 'image/png' : 'image/jpeg') : 'video/mp4';
      final ref = appStorage.ref('videos/${user.uid}/$id.$ext');
      final task =
          ref.putFile(file, SettableMetadata(contentType: contentType));
      task.snapshotEvents.listen((s) {
        if (mounted && s.totalBytes > 0)
          setState(() => _progress = s.bytesTransferred / s.totalBytes);
      });
      await task;
      final url = await ref.getDownloadURL();
      try {
        await FirebaseFirestore.instance.collection('videos').doc(id).set({
        'id': id,
        'ownerId': user.uid,
        'username': AppData.userName,
        'caption': _captionController.text.trim().isEmpty
            ? 'منشور جديد 🔥'
            : _captionController.text.trim(),
        'commentsAllowed': _commentsAllowed,
        'selectedSong': _selectedSong,
        'musicUrl': songUrlFor(_selectedSong),
        'musicVolume': _addedSongVolume,
        'downloadUrl': url,
        'mediaType': isImage ? 'image' : 'video',
        'filter': _filter,
        'trimStartMs': isImage ? 0 : _trimStartMs,
        'trimEndMs': isImage ? 0 : _trimEndMs,
        'originalVolume': _originalSoundVolume,
        'createdAt': FieldValue.serverTimestamp(),
        'likesCount': 0,
        'commentsCount': 0,
      });
      } catch (_) {
        // Do not leave an inaccessible object behind when the document write fails.
        try { await ref.delete(); } catch (_) {}
        rethrow;
      }
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم رفع ونشر المحتوى بنجاح ✅'),
          backgroundColor: Colors.green));
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        final hint = (e.code == 'unauthorized' || e.code == 'permission-denied')
            ? 'القواعد غير منشورة: شغّل firebase deploy --only firestore:rules,storage'
            : (e.code == 'object-not-found' ||
                    e.code == 'bucket-not-found' ||
                    e.code == 'project-not-found')
                ? 'فعّل Firebase Storage من الكونسول (Build > Storage)'
                : (e.message ?? '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 8),
            content: Text('فشل الرفع (${e.code}): $hint')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل النشر: $e')));
      }
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('معاينة ونشر المحتوى'),
        actions: [
          BgMusic(url: songUrlFor(_selectedSong), volume: _addedSongVolume),
          // زر تغيير الأغنية في أعلى الشاشة
          IconButton(
            icon: const Icon(Icons.music_note, color: Colors.amber),
            tooltip: 'تغيير الأغنية',
            onPressed: _openSongsPicker,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // معاينة حية مع الفلتر والقص
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 360,
                child: _isImage
                    ? applyFilter(
                        _filter,
                        Image.file(File(widget.mediaPath),
                            fit: BoxFit.cover, width: double.infinity))
                    : RemoteVideo(
                        filePath: widget.mediaPath,
                        trimStartMs: _trimStartMs,
                        trimEndMs: _trimEndMs,
                        filter: _filter,
                        volume: _originalSoundVolume,
                        onDuration: (d) {
                          if (mounted) setState(() => _duration = d);
                        },
                      ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('الفلاتر 🎨',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: kFilterLabels.entries
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(e.value),
                            selected: _filter == e.key,
                            selectedColor: Colors.redAccent,
                            onSelected: (_) => setState(() => _filter = e.key),
                          ),
                        ))
                    .toList(),
              ),
            ),
            if (!_isImage && _duration > Duration.zero) ...[
              const SizedBox(height: 12),
              Text(
                'قص الفيديو ✂️  (${(_duration.inMilliseconds * _trim.start / 1000).toStringAsFixed(1)}ث → ${(_duration.inMilliseconds * _trim.end / 1000).toStringAsFixed(1)}ث)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              RangeSlider(
                values: _trim,
                min: 0,
                max: 1,
                activeColor: Colors.redAccent,
                onChanged: (v) {
                  // لا نسمح بمقطع أقصر من ثانية
                  final minGap = 1000 / _duration.inMilliseconds;
                  if (v.end - v.start < minGap) return;
                  setState(() => _trim = v);
                },
              ),
              Row(children: [
                const Icon(Icons.volume_up, size: 20),
                Expanded(
                  child: Slider(
                    value: _originalSoundVolume,
                    activeColor: Colors.amber,
                    onChanged: (v) => setState(() => _originalSoundVolume = v),
                  ),
                ),
                Text('${(_originalSoundVolume * 100).round()}%'),
              ]),
            ],
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.grey[850],
                  borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.music_note, color: Colors.amber),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text('الأغنية الحالية: $_selectedSong',
                          style: const TextStyle(color: Colors.white))),
                  TextButton(
                      onPressed: _openSongsPicker,
                      child: const Text('تعديل الصوت',
                          style: TextStyle(color: Colors.amber))),
                ],
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _captionController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'اكتب وصف الفيديو الخاص بك...',
                filled: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[850]),
                  icon: const Icon(Icons.tag, color: Colors.amber),
                  label: const Text('هاشتاج #'),
                  onPressed: () => _insertText(' #ترند_تيك_توك '),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[850]),
                  icon: const Icon(Icons.alternate_email,
                      color: Colors.blueAccent),
                  label: const Text('إشارة @'),
                  onPressed: () => _insertText(' @صديقي '),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text('السماح بالتعليقات'),
              value: _commentsAllowed,
              activeColor: Colors.redAccent,
              onChanged: (val) => setState(() => _commentsAllowed = val),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.all(14)),
              onPressed: _uploading ? null : _publishVideo,
              child: _uploading
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              value: _progress > 0 ? _progress : null,
                              strokeWidth: 2.5)),
                      const SizedBox(width: 12),
                      Text('جاري الرفع ${(_progress * 100).round()}%'),
                    ])
                  : const Text('نشر الآن 🚀', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// 5. صفحة الرسائل والإشعارات الحقيقية
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null)
      return const Scaffold(body: Center(child: Text('سجل الدخول أولًا')));
    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .snapshots();
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (_, snapshot) {
          if (snapshot.hasError)
            return Center(child: Text('خطأ: ${snapshot.error}'));
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty)
            return const Center(child: Text('لا توجد إشعارات بعد'));
          return ListView(
            children: snapshot.data!.docs.map((doc) {
              final data = doc.data();
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.notifications)),
                title: Text(data['title'] ?? 'إشعار جديد'),
                subtitle: Text(data['body'] ?? ''),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// 6. صفحة الملف الشخصي المرتبطة بـ Firestore
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null)
      return const Scaffold(body: Center(child: Text('سجل الدخول أولًا')));
    final videos = FirebaseFirestore.instance
        .collection('videos')
        .where('ownerId', isEqualTo: user.uid)
        .snapshots();
    final profile = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();
    return Scaffold(
      appBar: AppBar(
        title: const Text('حسابي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'تعديل الملف الشخصي',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: profile,
        builder: (_, profileSnap) {
          final data = profileSnap.data?.data() ?? {};
          final photo = (data['photoUrl'] as String?) ?? user.photoURL ?? '';
          return Column(children: [
            const SizedBox(height: 15),
            CircleAvatar(
              radius: 45,
              backgroundImage: photo.isEmpty ? null : NetworkImage(photo),
              child: photo.isEmpty ? const Icon(Icons.person, size: 55) : null,
            ),
            const SizedBox(height: 10),
            Text(
              data['displayName'] ?? user.displayName ?? user.email ?? 'مستخدم',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if ((data['bio'] as String?)?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 24, right: 24),
                child: Text(data['bio'],
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70)),
              ),
            const SizedBox(height: 5),
            Text(user.email ?? '', style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 15),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text('المتابعون: ${data['followersCount'] ?? 0}'),
              const SizedBox(width: 24),
              Text('المتابَعون: ${data['followingCount'] ?? 0}'),
            ]),
            const SizedBox(height: 15),
            const Divider(),
            const Text('منشوراتي', style: TextStyle(color: Colors.grey)),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: videos,
                builder: (_, snap) {
                  if (snap.hasError)
                    return Center(child: Text('خطأ: ${snap.error}'));
                  if (!snap.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final docs = snap.data!.docs.toList()
                    ..sort((a, b) {
                      final ta = (a.data()['createdAt'] as Timestamp?)
                              ?.millisecondsSinceEpoch ??
                          1 << 50;
                      final tb = (b.data()['createdAt'] as Timestamp?)
                              ?.millisecondsSinceEpoch ??
                          1 << 50;
                      return tb.compareTo(ta);
                    });
                  if (docs.isEmpty)
                    return const Center(child: Text('لم تنشر شيئًا بعد'));
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(5, 5, 5, 110),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 5,
                      mainAxisSpacing: 5,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (_, i) => MediaThumb(data: docs[i].data()),
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}

/// مصغّر منشور: صورة أو أيقونة تشغيل للفيديو.
class MediaThumb extends StatelessWidget {
  final Map<String, dynamic> data;
  const MediaThumb({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    final url = data['downloadUrl'] as String? ?? '';
    final isImage = data['mediaType'] == 'image';
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        color: Colors.white10,
        child: url.isNotEmpty && isImage
            ? applyFilter(
                data['filter'] as String? ?? 'none',
                Image.network(url,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity))
            : Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.play_circle_fill,
                      size: 36, color: Colors.white70),
                  Text(data['caption'] ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(fontSize: 10, color: Colors.white54)),
                ]),
              ),
      ),
    );
  }
}

// تعديل الاسم والصورة والنبذة — يُحفظ في Firebase Auth + Firestore + Storage
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController(text: AppData.userName);
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController(text: AppData.userPhone);
  String _photoUrl = AppData.photoUrl;
  File? _newPhoto;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadBio();
  }

  Future<void> _loadBio() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final d =
          (await FirebaseFirestore.instance.collection('users').doc(uid).get())
              .data();
      if (mounted && d != null)
        _bioController.text = (d['bio'] as String?) ?? '';
    } catch (_) {}
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85);
    if (picked != null) setState(() => _newPhoto = File(picked.path));
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    final name = _nameController.text.trim();
    if (user == null) return;
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اكتب اسمًا من حرفين على الأقل')));
      return;
    }
    setState(() => _saving = true);
    try {
      // Save text fields first so an avatar upload failure cannot discard them.
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': name,
        'bio': _bioController.text.trim(),
        'phone': _phoneController.text.trim(),
        'photoUrl': _photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      var photo = _photoUrl;
      if (_newPhoto != null) {
        final ref = appStorage.ref(
            'profile_images/${user.uid}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(
            _newPhoto!, SettableMetadata(contentType: 'image/jpeg'));
        photo = await ref.getDownloadURL();
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set({'photoUrl': photo}, SetOptions(merge: true));
      }
      try {
        await user.updateDisplayName(name);
        if (photo.isNotEmpty) await user.updatePhotoURL(photo);
      } catch (e) {
        debugPrint('auth profile update: $e');
      }
      await AppData.loadProfile();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم حفظ التعديلات ✅'), backgroundColor: Colors.green));
    } on FirebaseException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('فشل الحفظ (${e.code}): ${e.message ?? 'تحقق من نشر Firestore/Storage والقواعد'}')));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ImageProvider? avatar = _newPhoto != null
        ? FileImage(_newPhoto!) as ImageProvider
        : (_photoUrl.isNotEmpty ? NetworkImage(_photoUrl) : null);
    return Scaffold(
      appBar: AppBar(title: const Text('تعديل الملف الشخصي')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Center(
          child: GestureDetector(
            onTap: _pickPhoto,
            child: Stack(children: [
              CircleAvatar(
                  radius: 56,
                  backgroundImage: avatar,
                  child: avatar == null
                      ? const Icon(Icons.person, size: 60)
                      : null),
              Positioned(
                bottom: 0,
                right: 0,
                child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.redAccent,
                    child: const Icon(Icons.camera_alt,
                        size: 18, color: Colors.white)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
            controller: _nameController,
            decoration: const InputDecoration(
                labelText: 'الاسم', prefixIcon: Icon(Icons.person))),
        const SizedBox(height: 14),
        TextField(
            controller: _bioController,
            maxLines: 2,
            maxLength: 120,
            decoration: const InputDecoration(
                labelText: 'نبذة عنك', prefixIcon: Icon(Icons.info_outline))),
        const SizedBox(height: 6),
        TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
                labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone))),
        const SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.all(14)),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5))
              : const Text('حفظ التعديلات', style: TextStyle(fontSize: 16)),
        ),
      ]),
    );
  }
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final _amountController = TextEditingController();
  final _destinationController = TextEditingController();
  String _method = 'instapay';
  bool _loading = false;
  Map<String, dynamic> _wallet = const {};

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _wallet = const {
              'availableCoins': 0,
              'pendingCoins': 0,
              'lifetimeEarnedCoins': 0,
            });
      }
      return;
    }
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('getWallet')
          .call();
      final data = result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : const <String, dynamic>{};
      if (mounted) setState(() => _wallet = data);
    } on FirebaseFunctionsException catch (functionError) {
      // The wallet function creates a wallet lazily, but the screen should
      // still work if functions are not deployed yet or the network is down.
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('wallets')
            .doc(user.uid)
            .get();
        final data = snapshot.data() ?? const <String, dynamic>{};
        if (mounted) {
          setState(() => _wallet = {
                'availableCoins': data['availableCoins'] ?? 0,
                'pendingCoins': data['pendingCoins'] ?? 0,
                'lifetimeEarnedCoins': data['lifetimeEarnedCoins'] ?? 0,
                'coinsPerEgp': coinsPerEgp,
              });
        }
      } catch (fallbackError) {
        if (mounted) {
          setState(() => _wallet = const {
                'availableCoins': 0,
                'pendingCoins': 0,
                'lifetimeEarnedCoins': 0,
              });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'تعذر تحميل الرصيد (${functionError.code}): $fallbackError')));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _wallet = const {
              'availableCoins': 0,
              'pendingCoins': 0,
              'lifetimeEarnedCoins': 0,
            });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('تعذر تحميل الرصيد: $e')));
      }
    }
  }

  Future<void> _requestWithdrawal() async {
    final amount = int.tryParse(_amountController.text.trim());
    final destination = _destinationController.text.trim();
    if (amount == null ||
        amount < minimumWithdrawalEgp ||
        destination.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اكتب مبلغًا لا يقل عن 50 جنيه وبيانات استلام صحيحة')));
      return;
    }
    final availableCoins = (_wallet['availableCoins'] as num?)?.toInt() ?? 0;
    if (amount * coinsPerEgp > availableCoins) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الرصيد المتاح لا يكفي لهذا المبلغ')));
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('requestWithdrawal')
          .call({
        'amountEgp': amount,
        'method': _method,
        'destination': destination,
      });
      _amountController.clear();
      _destinationController.clear();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'تم إرسال طلب السحب للمراجعة. التحويل يتم بعد اعتماد الإدارة.'),
            backgroundColor: Colors.green));
        _loadWallet();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message ?? 'فشل إنشاء طلب السحب')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showWithdrawalForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: StatefulBuilder(
            builder: (context, setSheetState) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('طلب سحب الأرباح',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                        'الحد الأدنى 50 جنيه. التحويل يتم يدويًا بعد مراجعة الإدارة.',
                        style: TextStyle(color: Colors.white70)),
                    Text(
                        'الرصيد المتاح: ${(((_wallet['availableCoins'] as num?)?.toInt() ?? 0) / coinsPerEgp).toStringAsFixed(2)} جنيه',
                        style: const TextStyle(color: Colors.amber)),
                    TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                            labelText: 'المبلغ بالجنيه المصري')),
                    DropdownButtonFormField<String>(
                        value: _method,
                        items: const [
                          DropdownMenuItem(
                              value: 'instapay', child: Text('InstaPay')),
                          DropdownMenuItem(
                              value: 'wallet', child: Text('محفظة كاش')),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => _method = value ?? 'instapay'),
                        decoration:
                            const InputDecoration(labelText: 'طريقة الاستلام')),
                    TextField(
                        controller: _destinationController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                            labelText: 'رقم الهاتف أو عنوان InstaPay')),
                    const SizedBox(height: 16),
                    SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                            onPressed: _loading ? null : _requestWithdrawal,
                            child: _loading
                                ? const CircularProgressIndicator()
                                : const Text('إرسال طلب السحب'))),
                  ],
                )),
      ),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = (_wallet['availableCoins'] as num?)?.toInt() ?? 0;
    final pending = (_wallet['pendingCoins'] as num?)?.toInt() ?? 0;
    final earned = (_wallet['lifetimeEarnedCoins'] as num?)?.toInt() ?? 0;
    Widget actionCard(IconData icon, String title, VoidCallback onTap,
        {bool badge = false}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Column(children: [
              Stack(children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(color: const Color(0xfff5f5f7),
                      borderRadius: BorderRadius.circular(14)),
                  child: Icon(icon, color: Colors.black, size: 30),
                ),
                if (badge)
                  Positioned(top: 0, right: 0,
                      child: Container(width: 12, height: 12,
                          decoration: const BoxDecoration(color: Colors.red,
                              shape: BoxShape.circle))),
              ]),
              const SizedBox(height: 10),
              Text(title, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black,
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
          ),
        );

    void comingSoon(String title) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title ستتوفر تفاصيله قريبًا')));

    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: Colors.white),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.black,
            title: const Text('رصيد', style: TextStyle(color: Colors.black,
                fontWeight: FontWeight.w800)),
            leading: IconButton(icon: const Icon(Icons.arrow_forward_ios),
                onPressed: () => Navigator.pop(context)),
            actions: [
              IconButton(onPressed: _loadWallet,
                  icon: const Icon(Icons.settings_outlined)),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _loadWallet,
            color: Colors.black,
            child: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
              children: [
                const Center(child: Text('آمن  ✓', style: TextStyle(
                    color: Colors.teal, fontWeight: FontWeight.w600))),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.visibility_outlined, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Text('الرصيد المقدّر EGP', style: TextStyle(
                      color: Colors.grey, fontSize: 20)),
                ]),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => WalletDetailsScreen(
                          availableCoins: available,
                          pendingCoins: pending,
                          onWithdraw: _showWithdrawalForm))),
                  child: Center(child: Text(
                      '${(available / coinsPerEgp).toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.black, fontSize: 54,
                          fontWeight: FontWeight.w800))),
                ),
                const SizedBox(height: 16),
                Center(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(color: const Color(0xfffff8e8),
                      borderRadius: BorderRadius.circular(24)),
                  child: RichText(text: TextSpan(style: const TextStyle(
                      color: Colors.black, fontSize: 16), children: [
                    const TextSpan(text: '🪙 العملات '),
                    TextSpan(text: '$available', style: const TextStyle(
                        fontWeight: FontWeight.bold)),
                    const TextSpan(text: '   |   الحصول على عملات ←',
                        style: TextStyle(color: Colors.grey)),
                  ]),
                ))),
                const SizedBox(height: 30),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  decoration: BoxDecoration(color: const Color(0xfffafafa),
                      borderRadius: BorderRadius.circular(18)),
                  child: Column(children: [
                    ListTile(contentPadding: EdgeInsets.zero,
                        title: const Text('المعاملات', style: TextStyle(
                            color: Colors.black, fontSize: 18,
                            fontWeight: FontWeight.bold)),
                        trailing: const Text('عرض الكل  ‹', style: TextStyle(
                            color: Colors.grey))),
                    Row(children: [
                      Expanded(child: actionCard(Icons.attach_money, 'مكافآت LIVE',
                          () => comingSoon('مكافآت LIVE'))),
                      Expanded(child: actionCard(Icons.bar_chart, 'الربح',
                          () => comingSoon('الربح'))),
                      Expanded(child: actionCard(Icons.stars, 'الفعاليات',
                          () => comingSoon('الفعاليات'), badge: true)),
                    ]),
                    Row(children: [
                      const Spacer(),
                      Expanded(child: actionCard(Icons.card_membership,
                          'مدير الاشتراكات',
                          () => comingSoon('مدير الاشتراكات'))),
                      const Spacer(),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),
                Text('إجمالي الأرباح: $earned عملة  •  قيد المراجعة: $pending عملة',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: available >= minimumWithdrawalEgp * coinsPerEgp
                      ? _showWithdrawalForm : null,
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('طلب سحب الأرباح'),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.black),
                ),
                const SizedBox(height: 20),
                const Text('رصيد ليس ملكًا ماليًا. التفاصيل المعروضة لأغراض إعلامية فقط.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ActivityLogScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  const ActivityLogScreen({super.key, required this.title, required this.icon});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 70, color: Colors.redAccent),
            const SizedBox(height: 18),
            Text(title, style: const TextStyle(fontSize: 23,
                fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('لا توجد بيانات مسجلة حتى الآن.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.6)),
          ]),
        )),
      );
}

class ActivityCenterScreen extends StatelessWidget {
  const ActivityCenterScreen({super.key});

  Widget _item(BuildContext context, String title, IconData icon) => ListTile(
        leading: Icon(icon, color: Colors.white),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_left, color: Colors.white54),
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ActivityLogScreen(title: title, icon: icon))),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('مركز الأنشطة')),
        body: ListView(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 22, 18, 8),
            child: Text('سجلات النشاط', style: TextStyle(color: Colors.white60,
                fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          _item(context, 'سجل المشاهدة', Icons.history),
          _item(context, 'سجل التعليقات', Icons.comment_outlined),
          _item(context, 'سجل البحث', Icons.search),
          _item(context, 'سجل نشاط الإعلان', Icons.ads_click),
          _item(context, 'سجل الذكر', Icons.alternate_email),
          const Divider(height: 24),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 4, 18, 8),
            child: Text('نشاط الحساب والوقت', style: TextStyle(color: Colors.white60,
                fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          _item(context, 'سجل الحساب', Icons.manage_accounts_outlined),
          _item(context, 'مدة الاستخدام', Icons.timer_outlined),
          _item(context, 'سجل إعادة استخدام المحتوى', Icons.repeat),
        ]),
      );

}

class WalletDetailsScreen extends StatelessWidget {
  final int availableCoins;
  final int pendingCoins;
  final VoidCallback? onWithdraw;
  const WalletDetailsScreen({super.key, required this.availableCoins,
      required this.pendingCoins, this.onWithdraw});

  @override
  Widget build(BuildContext context) {
    final egp = availableCoins / coinsPerEgp;
    return Theme(
      data: Theme.of(context).copyWith(scaffoldBackgroundColor: Colors.white),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.black,
            title: const Text('الرصيد', style: TextStyle(color: Colors.black,
                fontWeight: FontWeight.w800)),
            leading: IconButton(icon: const Icon(Icons.arrow_forward_ios),
                onPressed: () => Navigator.pop(context)),
            actions: [IconButton(onPressed: () {},
                icon: const Icon(Icons.more_horiz))],
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(22, 20, 22, 40),
              children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.visibility_outlined, color: Colors.grey, size: 20),
              const SizedBox(width: 8),
              const Text('اضغط على "إجمالي الرصيد المقدّر"',
                  style: TextStyle(color: Colors.grey, fontSize: 18)),
              const SizedBox(width: 6),
              const Icon(Icons.info_outline, color: Colors.grey, size: 18),
            ]),
            const SizedBox(height: 12),
            Center(child: RichText(text: TextSpan(style: const TextStyle(
                color: Colors.black, fontWeight: FontWeight.w800), children: [
              const TextSpan(text: 'EGP', style: TextStyle(fontSize: 21)),
              TextSpan(text: egp.toStringAsFixed(2),
                  style: const TextStyle(fontSize: 52)),
            ]))),
            const SizedBox(height: 34),
            Material(
              color: const Color(0xfffafafa),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: onWithdraw,
                borderRadius: BorderRadius.circular(18),
                child: Padding(padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                      const Text('السحب في أي وقت', style: TextStyle(
                          color: Colors.black, fontSize: 20,
                          fontWeight: FontWeight.bold)),
                      Text('EGP${egp.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.grey,
                              fontSize: 18)),
                    ]),
                    const SizedBox(height: 22),
                    Row(children: [
                      Container(width: 58, height: 58,
                          decoration: BoxDecoration(color: const Color(0xfff1f1f1),
                              borderRadius: BorderRadius.circular(16)),
                          child: const Icon(Icons.attach_money,
                              color: Colors.black, size: 34)),
                      const SizedBox(width: 14),
                      const Expanded(child: Column(crossAxisAlignment:
                          CrossAxisAlignment.start, children: [
                        Text('مكافآت LIVE', style: TextStyle(color: Colors.black,
                            fontSize: 18, fontWeight: FontWeight.w600)),
                        SizedBox(height: 4),
                        Text('EGP0.00  |  USD0.00', style: TextStyle(
                            color: Colors.grey, fontSize: 15)),
                      ])),
                      const Icon(Icons.chevron_left, color: Colors.grey),
                    ]),
                  ]),
                ),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [
                    Color(0xfffffdf4), Color(0xfffff6c9),
                  ]), borderRadius: BorderRadius.circular(18)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Align(alignment: Alignment.centerRight,
                    child: Icon(Icons.attach_money, color: Color(0xffffc400),
                        size: 72)),
                const Text('اربح المزيد من المكافآت', style: TextStyle(
                    color: Colors.black, fontSize: 20,
                    fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text('اطلع على مركز الربح للتعرف على الفرص والبرامج المثيرة.',
                    style: TextStyle(color: Colors.grey, fontSize: 15,
                        height: 1.5)),
                const SizedBox(height: 16),
                TextButton(onPressed: () => ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text(
                        'مركز الربح سيظهر عند تفعيل برامج الأرباح'))),
                    child: const Text('اكتشف  ‹', style: TextStyle(
                        color: Colors.pink, fontSize: 17,
                        fontWeight: FontWeight.bold))),
              ]),
            ),
            const SizedBox(height: 16),
            Text('الرصيد قيد المراجعة: $pendingCoins عملة',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

// صفحات عناصر قائمة الثلاث شرط.
class FeatureMenuScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String description;
  final String actionLabel;
  const FeatureMenuScreen({super.key, required this.title, required this.icon,
      required this.description, required this.actionLabel});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 70, color: Colors.redAccent),
                  const SizedBox(height: 18),
                  Text(title, style: const TextStyle(fontSize: 24,
                      fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Text(description, textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70,
                          height: 1.6)),
                  const SizedBox(height: 22),
                  OutlinedButton.icon(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('الميزة ستتوفر مع تحديث المحتوى القادم'))),
                    icon: const Icon(Icons.info_outline),
                    label: Text(actionLabel),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

class MyQrScreen extends StatelessWidget {
  const MyQrScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final username = AppData.username.isEmpty ? AppData.userName : AppData.username;
    final value = user?.uid ?? username;
    final profileLink = 'https://st-video.app/@$username';
    return Scaffold(
      appBar: AppBar(title: const Text('رمز QR لديك')),
      body: Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 240, height: 240, padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: QrImageView(data: profileLink, version: QrVersions.auto,
                  size: 216, backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square,
                      color: Colors.black),
                  dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black))),
          const SizedBox(height: 20),
          Text('@$username',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SelectableText('معرّف الحساب: $value',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: profileLink));
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ رابط الحساب')));
              },
              icon: const Icon(Icons.copy), label: const Text('نسخ الرابط'),
            )),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(
              onPressed: () => Share.share('تابع حسابي على ST Video\n$profileLink'),
              icon: const Icon(Icons.share), label: const Text('مشاركة'),
            )),
          ]),
        ]),
      )),
    );
  }
}

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الإعدادات والخصوصية')),
        body: ListView(children: [
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('المعلومات الشخصية'),
            subtitle: Text('الاسم: ${AppData.userName}\nالبريد: ${AppData.userEmail}'),
            isThreeLine: true,
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const EditProfileScreen())),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('الأمان: كلمة المرور والبريد'),
            subtitle: const Text('تغيير كلمة المرور أو البريد الإلكتروني'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AccountSecurityScreen())),
          ),
          const Divider(height: 32),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              icon: const Icon(Icons.logout),
              label: const Text('تسجيل الخروج من الحساب'),
              onPressed: () async {
                AppData.isLoggedIn = false;
                try { await GoogleSignIn().signOut(); } catch (_) {}
                await FirebaseAuth.instance.signOut();
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(context,
                    MaterialPageRoute(builder: (_) => const AuthScreen()),
                    (route) => false);
              },
            )),
        ]),
      );
}

// 7. قائمة الثلاث شرط مثل تنظيم TikTok.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 6),
        child: Text(title, style: const TextStyle(color: Colors.white60,
            fontSize: 15, fontWeight: FontWeight.w600)),
      );

  Widget _item(BuildContext context, String title, IconData icon, Widget page) =>
      ListTile(
        leading: Icon(icon, color: Colors.white),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_left, color: Colors.white54),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => page)),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('القائمة')),
        body: ListView(children: [
          _section('الأصول'),
          _item(context, 'الرصيد', Icons.account_balance_wallet_outlined,
              const WalletScreen()),
          const Divider(height: 1),
          _section('الأدوات الشخصية'),
          _item(context, 'مركز الأنشطة', Icons.access_time,
              const ActivityCenterScreen()),
          _item(context, 'فيديوهات دون اتصال بالإنترنت', Icons.cloud_download_outlined,
              const FeatureMenuScreen(title: 'فيديوهات دون اتصال بالإنترنت', icon: Icons.cloud_download_outlined,
                  description: 'ستظهر هنا الفيديوهات التي تختار حفظها للمشاهدة بدون إنترنت.',
                  actionLabel: 'إدارة التنزيلات')),
          _item(context, 'رمز QR لديك', Icons.qr_code_2,
              const MyQrScreen()),
          const Divider(height: 1),
          _section('أدوات الإبداع والأعمال'),
          _item(context, 'TikTok Studio', Icons.person_search_outlined,
              const FeatureMenuScreen(title: 'TikTok Studio', icon: Icons.person_search_outlined,
                  description: 'لوحة أدوات لصنّاع المحتوى لمتابعة المنشورات والأداء والأرباح.',
                  actionLabel: 'فتح الاستوديو')),
          _item(context, 'الترويج', Icons.local_fire_department_outlined,
              const FeatureMenuScreen(title: 'الترويج', icon: Icons.local_fire_department_outlined,
                  description: 'روّج لمنشوراتك ووصل إلى جمهور أكبر بعد إعداد الحملات.',
                  actionLabel: 'إنشاء ترويج')),
          const Divider(height: 1),
          _item(context, 'الإعدادات والخصوصية', Icons.settings_outlined,
              const PrivacySettingsScreen()),
        ]),
      );
}

// تغيير كلمة المرور والبريد الإلكتروني (مع إعادة التحقق من الهوية)
class AccountSecurityScreen extends StatefulWidget {
  const AccountSecurityScreen({super.key});
  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final _curPass = TextEditingController();
  final _newPass = TextEditingController();
  final _newPass2 = TextEditingController();
  final _emailPass = TextEditingController();
  final _newEmail = TextEditingController();
  bool _busy = false;

  User? get _user => FirebaseAuth.instance.currentUser;
  bool get _hasPassword =>
      _user?.providerData.any((p) => p.providerId == 'password') ?? false;

  void _msg(String t, {bool ok = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t), backgroundColor: ok ? Colors.green : null));
  }

  String _err(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'كلمة المرور الحالية غير صحيحة';
      case 'weak-password':
        return 'كلمة المرور الجديدة ضعيفة (6 أحرف على الأقل)';
      case 'email-already-in-use':
        return 'هذا البريد مستخدم بالفعل';
      case 'invalid-email':
        return 'البريد الإلكتروني غير صالح';
      case 'requires-recent-login':
        return 'سجّل الخروج ثم الدخول وحاول مرة أخرى';
      case 'too-many-requests':
        return 'محاولات كثيرة، حاول لاحقًا';
      default:
        return 'خطأ (${e.code}): ${e.message ?? ''}';
    }
  }

  Future<void> _reauth(String password) async {
    final u = _user!;
    await u.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: u.email ?? '', password: password));
  }

  Future<void> _changePassword() async {
    if (_user == null) return;
    if (_newPass.text.length < 6)
      return _msg('كلمة المرور الجديدة 6 أحرف على الأقل');
    if (_newPass.text != _newPass2.text)
      return _msg('تأكيد كلمة المرور غير مطابق');
    setState(() => _busy = true);
    try {
      await _reauth(_curPass.text);
      await _user!.updatePassword(_newPass.text);
      _curPass.clear();
      _newPass.clear();
      _newPass2.clear();
      _msg('تم تغيير كلمة المرور ✅', ok: true);
    } on FirebaseAuthException catch (e) {
      _msg(_err(e));
    } catch (e) {
      _msg('فشل: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeEmail() async {
    final email = _newEmail.text.trim();
    if (_user == null) return;
    if (!email.contains('@')) return _msg('اكتب بريدًا صحيحًا');
    setState(() => _busy = true);
    try {
      await _reauth(_emailPass.text);
      await _user!.verifyBeforeUpdateEmail(email);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .set({'pendingEmail': email}, SetOptions(merge: true));
      _emailPass.clear();
      _newEmail.clear();
      _msg('أرسلنا رابط تأكيد إلى $email — افتحه لإتمام التغيير ✅', ok: true);
    } on FirebaseAuthException catch (e) {
      _msg(_err(e));
    } catch (e) {
      _msg('فشل: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendReset() async {
    final email = _user?.email;
    if (email == null) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _msg('أرسلنا رابط تعيين كلمة المرور إلى $email', ok: true);
    } on FirebaseAuthException catch (e) {
      _msg(_err(e));
    }
  }

  @override
  void dispose() {
    _curPass.dispose();
    _newPass.dispose();
    _newPass2.dispose();
    _emailPass.dispose();
    _newEmail.dispose();
    super.dispose();
  }

  Widget _pass(TextEditingController c, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
            controller: c,
            obscureText: true,
            decoration: InputDecoration(
                labelText: label, prefixIcon: const Icon(Icons.lock))),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الأمان وكلمة المرور')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('البريد الحالي: ${_user?.email ?? '—'}',
            style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 16),
        if (!_hasPassword) ...[
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                  'حسابك مسجّل عبر Google ولا توجد له كلمة مرور. يمكنك إنشاء كلمة مرور عبر رابط يصلك على بريدك.'),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _sendReset,
            icon: const Icon(Icons.mail),
            label: const Text('أرسل رابط تعيين كلمة المرور'),
          ),
        ] else ...[
          const Text('تغيير كلمة المرور 🔐',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _pass(_curPass, 'كلمة المرور الحالية'),
          _pass(_newPass, 'كلمة المرور الجديدة'),
          _pass(_newPass2, 'تأكيد كلمة المرور الجديدة'),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.all(14)),
            onPressed: _busy ? null : _changePassword,
            child: const Text('حفظ كلمة المرور'),
          ),
          TextButton(
              onPressed: _sendReset,
              child: const Text('نسيت كلمة المرور؟ أرسل رابط إعادة تعيين')),
          const Divider(height: 40),
          const Text('تغيير البريد الإلكتروني ✉️',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextField(
                controller: _newEmail,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'البريد الجديد', prefixIcon: Icon(Icons.email))),
          ),
          _pass(_emailPass, 'كلمة المرور الحالية للتأكيد'),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.all(14)),
            onPressed: _busy ? null : _changeEmail,
            child: const Text('إرسال رابط تأكيد البريد'),
          ),
        ],
      ]),
    );
  }
}

// 8. البث المباشر عبر Agora (بدون Certificate - Testing mode)
class LiveStreamScreen extends StatefulWidget {
  const LiveStreamScreen({super.key});

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  RtcEngine? _engine;
  bool _joined = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startLive();
  }

  Future<void> _startLive() async {
    try {
      final permissions =
          await [Permission.camera, Permission.microphone].request();
      if (permissions[Permission.camera]?.isGranted != true ||
          permissions[Permission.microphone]?.isGranted != true) {
        throw Exception('يجب السماح بالكاميرا والميكروفون لبدء البث');
      }
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('سجل الدخول أولًا');
      final channelName = 'live_${user.uid}';
      final tokenResult = await FirebaseFunctions.instance
          .httpsCallable('getAgoraToken')
          .call({'channelName': channelName, 'role': 'broadcaster'});
      final token = (tokenResult.data as Map)['token'] as String?;
      if (token == null || token.isEmpty) throw Exception('تعذر إصدار رمز البث');
      final engine = createAgoraRtcEngine();
      _engine = engine;
      await engine.initialize(const RtcEngineContext(
        appId: agoraAppId,
        channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
      ));
      engine.registerEventHandler(RtcEngineEventHandler(
        onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
          if (mounted) setState(() => _joined = true);
        },
        onError: (ErrorCodeType err, String msg) {
          if (mounted) setState(() => _error = 'Agora error: $err $msg');
        },
      ));
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
      await engine.enableVideo();
      await engine.startPreview();
      await engine.joinChannel(
        token: token,
        channelId: channelName,
        uid: 0,
        options: const ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر بدء البث: $e');
    }
  }

  @override
  void dispose() {
    final engine = _engine;
    if (engine != null) {
      engine.leaveChannel();
      engine.release();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_error != null) {
      body = Center(
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(_error!, textAlign: TextAlign.center)));
    } else if (_joined && _engine != null) {
      body = AgoraVideoView(
        controller: VideoViewController(
          rtcEngine: _engine!,
          canvas: const VideoCanvas(uid: 0),
        ),
      );
    } else {
      body = const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('🔴 البث المباشر')),
      body: body,
    );
  }
}

// 9. صفحة اكتشف الترندات
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _search = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('اكتشف')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _search,
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: InputDecoration(
              hintText: 'ابحث عن مستخدم بالاسم...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _q.isNotEmpty
              ? FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  key: ValueKey(_q),
                  future: db
                      .collection('users')
                      .where('displayName', isGreaterThanOrEqualTo: _q)
                      .where('displayName', isLessThan: '$_q\uf8ff')
                      .limit(30)
                      .get(),
                  builder: (context, snap) {
                    if (snap.hasError)
                      return Center(child: Text('تعذر البحث: ${snap.error}'));
                    if (!snap.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final docs = snap.data!.docs;
                    if (docs.isEmpty)
                      return const Center(child: Text('لا توجد نتائج'));
                    return ListView(
                      children: docs.map((d) {
                        final u = d.data();
                        final photo = (u['photoUrl'] as String?) ?? '';
                        final name = (u['displayName'] as String?) ?? 'user';
                        return ListTile(
                          leading: CircleAvatar(
                              backgroundImage:
                                  photo.isNotEmpty ? NetworkImage(photo) : null,
                              child: photo.isEmpty
                                  ? const Icon(Icons.person)
                                  : null),
                          title: Text(name),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => PublicProfileScreen(
                                      userId: d.id, username: name))),
                        );
                      }).toList(),
                    );
                  },
                )
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: db
                      .collection('videos')
                      .orderBy('createdAt', descending: true)
                      .limit(60)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError)
                      return Center(child: Text('تعذر التحميل: ${snap.error}'));
                    if (!snap.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final docs = snap.data!.docs;
                    if (docs.isEmpty)
                      return const Center(child: Text('لا توجد منشورات بعد'));
                    return GridView.builder(
                      padding: const EdgeInsets.all(10),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.75),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final d = docs[i].data();
                        return GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => PublicProfileScreen(
                                    userId: d['ownerId'] ?? '',
                                    username: d['username'] ?? 'user')),
                          ),
                          child: MediaThumb(data: d),
                        );
                      },
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
