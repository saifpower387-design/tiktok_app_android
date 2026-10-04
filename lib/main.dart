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
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
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
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final d = doc.data();
      if (d != null) {
        userName = (d['displayName'] as String?)?.trim().isNotEmpty == true ? d['displayName'] as String : userName;
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

class _AppBackgroundState extends State<AppBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 18))..repeat(reverse: true);

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
            gradient: RadialGradient(colors: [color.withValues(alpha: 0.45), color.withValues(alpha: 0)]),
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
                colors: [Color(0xFF070A18), Color(0xFF111A3B), Color(0xFF210D2D)],
              ),
            ),
            child: Stack(children: [
              _orb(const Color(0xFF00D9FF), 360, Alignment(-1 + t * 0.8, -0.9 + t * 0.5)),
              _orb(const Color(0xFFFF167D), 400, Alignment(1 - t * 0.8, 0.9 - t * 0.5)),
              _orb(const Color(0xFF7B2FF7), 300, Alignment(0.8 - t * 1.4, -0.2 + t * 0.4)),
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
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      builder: (_, __) {
        final inV = 1 - Curves.easeOutCubic.transform(animation.value);
        final outV = Curves.easeInCubic.transform(secondaryAnimation.value);
        final m = Matrix4.identity()
          ..setEntry(3, 2, 0.0015)
          ..translate(inV * MediaQuery.of(context).size.width * 0.5 - outV * MediaQuery.of(context).size.width * 0.25)
          ..rotateY(-inV * math.pi / 3 + outV * math.pi / 6);
        return Opacity(
          opacity: (1 - outV * 0.5).clamp(0.0, 1.0),
          child: Transform(transform: m, alignment: Alignment.center, child: child),
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
          boxShadow: const [BoxShadow(color: Color(0x5500D9FF), blurRadius: 24, offset: Offset(0, 6))],
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
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        isCenter
                            ? Container(
                                width: 50,
                                height: 38,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: const LinearGradient(colors: [Color(0xFF00D9FF), Color(0xFFFF167D)]),
                                  boxShadow: [BoxShadow(color: const Color(0xFFFF167D).withValues(alpha: 0.5), blurRadius: 12)],
                                ),
                                child: const Icon(Icons.add_rounded, color: Colors.white, size: 28),
                              )
                            : Icon(_items[i].$1,
                                size: 26 + 4 * v,
                                color: Color.lerp(Colors.white54, const Color(0xFF00D9FF), v)),
                        if (!isCenter)
                          Text(_items[i].$2,
                              style: TextStyle(fontSize: 10, color: Color.lerp(Colors.white54, Colors.white, v))),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.08),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
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
        SnackBar(content: Text('تسجيل $providerName يحتاج إعداد OAuth الخاص به أولًا')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final account = await GoogleSignIn(
        serverClientId: '67126189193-akc65ebuqfnm9988212nbt47bqk061ul.apps.googleusercontent.com',
      ).signIn().timeout(const Duration(seconds: 30));
      if (account == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final auth = await account.authentication.timeout(const Duration(seconds: 20));
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
      AppData.userName = user.displayName ?? user.email?.split('@').first ?? 'مستخدم';
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
      try {
        final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
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
        await ref.set(data, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
        await AppData.loadProfile();
      } catch (_) {
        // دخول Google تم بنجاح؛ فشل حفظ الملف الشخصي لا يمنع فتح التطبيق.
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل Google: ${e.message ?? e.code}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تسجيل Google: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitAuthForm() async {
    final identifier = _emailController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();
    if (identifier.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل البريد أو اسم المستخدم وكلمة مرور من 6 أحرف على الأقل')));
      return;
    }
    if (!_isLogin && (username.length < 3 || !identifier.contains('@'))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل اسم مستخدم من 3 أحرف وبريدًا إلكترونيًا صحيحًا')));
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
          throw FirebaseAuthException(code: 'user-not-found', message: 'اسم المستخدم غير موجود');
        }
        email = nameDoc.data()?['email'] as String? ?? '';
        if (email.isEmpty) {
          throw FirebaseAuthException(code: 'invalid-user-data', message: 'بيانات المستخدم غير مكتملة');
        }
      }
      if (!_isLogin) {
        final existing = await FirebaseFirestore.instance.collection('usernames').doc(username).get();
        if (existing.exists) {
          throw FirebaseAuthException(code: 'username-already-in-use', message: 'اسم المستخدم مستخدم بالفعل');
        }
      }
      final result = _isLogin
          ? await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password)
          : await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      final user = result.user!;
      if (!_isLogin) {
        try {
          await user.updateDisplayName(username);
        } catch (_) {}
      }
      AppData.isLoggedIn = true;
      final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final existingProfile = await userRef.get();
      final userData = <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      // لا نكتب فوق الاسم المعدل: نضبط الاسم فقط عند إنشاء الحساب أو لو مفيش اسم محفوظ.
      if (!existingProfile.exists || existingProfile.data()?['displayName'] == null) {
        userData['displayName'] = _isLogin ? user.displayName ?? email.split('@').first : username;
      }
      if (!_isLogin) {
        userData['username'] = username;
        try {
          await FirebaseFirestore.instance.collection('usernames').doc(username).set({'uid': user.uid, 'email': user.email});
        } catch (_) {}
      }
      await userRef.set(userData, SetOptions(merge: true));
      await AppData.loadProfile();
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } on FirebaseAuthException catch (e) {
      final message = switch (e.code) {
        'user-not-found' => 'اسم المستخدم أو البريد غير موجود',
        'wrong-password' || 'invalid-credential' => 'اسم المستخدم أو كلمة المرور غير صحيحة',
        'email-already-in-use' => 'هذا البريد مستخدم بالفعل',
        'username-already-in-use' => 'اسم المستخدم مستخدم بالفعل',
        'operation-not-allowed' => 'فعّل Email/Password من Firebase Console',
        _ => e.message ?? 'فشل تسجيل الدخول',
      };
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
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
                            BoxShadow(color: Color(0x6600D9FF), blurRadius: 28, spreadRadius: 2),
                          ],
                        ),
                        child: const Icon(Icons.music_video, size: 58, color: Colors.white),
                      ),
                const SizedBox(height: 20),
                Text(_isLogin ? 'تسجيل الدخول لتيك توك' : 'إنشاء حساب جديد 🚀', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                if (!_isLogin)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(hintText: 'اسم المستخدم', filled: true, prefixIcon: Icon(Icons.person)),
                    ),
                  ),
                TextField(
                  controller: _emailController,
                  keyboardType: _isLogin ? TextInputType.text : TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: _isLogin ? 'البريد الإلكتروني أو اسم المستخدم' : 'البريد الإلكتروني',
                    filled: true,
                    prefixIcon: const Icon(Icons.email),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(hintText: 'كلمة المرور', filled: true)),
                const SizedBox(height: 25),
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.redAccent)
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, minimumSize: const Size(double.infinity, 50)),
                        onPressed: _submitAuthForm,
                        child: Text(_isLogin ? 'دخول' : 'تسجيل', style: const TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(_isLogin ? 'ليس لديك حساب؟ أنشئ حساباً' : 'لديك حساب؟ سجل دخولك', style: const TextStyle(color: Colors.amber)),
                ),
                const Divider(height: 30, color: Colors.white24),
                const Text('أو المتابعة باستخدام', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 15),
                OutlinedButton.icon(
                  icon: const Icon(Icons.g_mobiledata, size: 34, color: Colors.white),
                  label: const Text('تسجيل الدخول باستخدام Google', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    side: const BorderSide(color: Colors.white38),
                    backgroundColor: Colors.white10,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  onPressed: _isLoading ? null : () => _loginWithSocial('Google (Gmail)', Colors.redAccent),
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
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.20), blurRadius: 110, spreadRadius: 35)],
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
                alignment: (isIn == (_dir > 0)) ? Alignment.centerLeft : Alignment.centerRight,
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
  'bw': [0.33, 0.59, 0.11, 0, 0, 0.33, 0.59, 0.11, 0, 0, 0.33, 0.59, 0.11, 0, 0, 0, 0, 0, 1, 0],
  'vivid': [1.3, -0.1, -0.1, 0, 0, -0.1, 1.3, -0.1, 0, 0, -0.1, -0.1, 1.3, 0, 0, 0, 0, 0, 1, 0],
  'vintage': [0.9, 0.3, 0.1, 0, 0, 0.2, 0.8, 0.1, 0, 0, 0.15, 0.25, 0.6, 0, 0, 0, 0, 0, 1, 0],
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
    final end = widget.trimEndMs > 0 ? widget.trimEndMs : v.duration.inMilliseconds;
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
      if (widget.trimStartMs > 0) await _controller.seekTo(Duration(milliseconds: widget.trimStartMs));
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
    if (_failed) return const Center(child: Icon(Icons.error_outline, size: 48, color: Colors.white54));
    if (!_controller.value.isInitialized) return const Center(child: CircularProgressIndicator());
    return GestureDetector(
      onTap: () {
        setState(() {
          _controller.value.isPlaying ? _controller.pause() : _controller.play();
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
      return const Center(child: Text('إعلان', style: TextStyle(color: Colors.white54)));
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('إعلان', style: TextStyle(color: Colors.white60, fontSize: 12)),
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

  Future<void> _toggleLike(String videoId, bool liked) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final videoRef = FirebaseFirestore.instance.collection('videos').doc(videoId);
    final likeRef = videoRef.collection('likes').doc(user.uid);
    final userLike = await likeRef.get();
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(videoRef);
      final current = (snapshot.data()?['likesCount'] as num? ?? 0).toInt();
      if (userLike.exists) {
        transaction.delete(likeRef);
        transaction.update(videoRef, {'likesCount': current > 0 ? current - 1 : 0});
      } else {
        transaction.set(likeRef, {'userId': user.uid, 'createdAt': FieldValue.serverTimestamp()});
        transaction.update(videoRef, {'likesCount': current + 1});
      }
    });
    try {
      final ownerId = (await videoRef.get()).data()?['ownerId'];
      if (!liked && ownerId != null && ownerId != user.uid) {
        await FirebaseFirestore.instance.collection('users').doc(ownerId).collection('notifications').add({
          'title': 'إعجاب جديد',
          'body': '${AppData.userName} أعجب بمنشورك',
          'type': 'like',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('like notification: $e');
    }
  }

  Future<void> _addComment(String videoId, String text) async {
    final user = FirebaseAuth.instance.currentUser;
    final value = text.trim();
    if (user == null || value.isEmpty) return;
    final videoRef = FirebaseFirestore.instance.collection('videos').doc(videoId);
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
        await FirebaseFirestore.instance.collection('users').doc(ownerId).collection('notifications').add({
          'title': 'تعليق جديد',
          'body': '${AppData.userName} كتب تعليقًا على منشورك',
          'type': 'comment',
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
        builder: (_) => const SizedBox(height: 180, child: Center(child: Text('التعليقات مغلقة لهذا المنشور'))),
      );
      return;
    }
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey[900],
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .65,
          child: Column(children: [
            const Padding(padding: EdgeInsets.all(14), child: Text('التعليقات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance.collection('videos').doc(videoId).collection('comments').orderBy('createdAt', descending: true).snapshots(),
                builder: (_, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  if (snapshot.data!.docs.isEmpty) return const Center(child: Text('كن أول من يعلق'));
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
              Expanded(child: TextField(controller: controller, decoration: const InputDecoration(hintText: 'اكتب تعليقًا...'))),
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
    final query = FirebaseFirestore.instance.collection('videos').orderBy('createdAt', descending: true);
    return Scaffold(
      body: Stack(children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text('خطأ في تحميل المنشورات: ${snapshot.error}'));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final term = _searchController.text.trim().toLowerCase();
            final docs = snapshot.data!.docs.where((doc) {
              if (term.isEmpty) return true;
              final data = doc.data();
              return '${data['caption'] ?? ''} ${data['username'] ?? ''}'.toLowerCase().contains(term);
            }).toList();
            if (docs.isEmpty) return const Center(child: Text('لا توجد منشورات مطابقة'));
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
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
  const PublicProfileScreen({super.key, required this.userId, required this.username});
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
    final doc = await FirebaseFirestore.instance.collection('users').doc(me.uid).collection('following').doc(widget.userId).get();
    if (mounted) setState(() => _following = doc.exists);
  }

  Future<void> _toggleFollow() async {
    final me = FirebaseAuth.instance.currentUser;
    if (me == null || me.uid == widget.userId) return;
    setState(() => _busy = true);
    final db = FirebaseFirestore.instance;
    final following = db.collection('users').doc(me.uid).collection('following').doc(widget.userId);
    final follower = db.collection('users').doc(widget.userId).collection('followers').doc(me.uid);
    final myRef = db.collection('users').doc(me.uid);
    final targetRef = db.collection('users').doc(widget.userId);
    await db.runTransaction((tx) async {
      final target = await tx.get(targetRef);
      final mine = await tx.get(myRef);
      final followers = (target.data()?['followersCount'] as num? ?? 0).toInt();
      final followingCount = (mine.data()?['followingCount'] as num? ?? 0).toInt();
      if (_following) {
        tx.delete(following);
        tx.delete(follower);
        tx.update(targetRef, {'followersCount': followers > 0 ? followers - 1 : 0});
        tx.update(myRef, {'followingCount': followingCount > 0 ? followingCount - 1 : 0});
      } else {
        tx.set(following, {'userId': widget.userId, 'createdAt': FieldValue.serverTimestamp()});
        tx.set(follower, {'userId': me.uid, 'createdAt': FieldValue.serverTimestamp()});
        tx.update(targetRef, {'followersCount': followers + 1});
        tx.update(myRef, {'followingCount': followingCount + 1});
      }
    });
    if (!_following) {
      await db.collection('users').doc(widget.userId).collection('notifications').add({
        'title': 'متابع جديد',
        'body': '${AppData.userName} بدأ متابعتك',
        'type': 'follow',
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    if (mounted) {
      setState(() {
        _following = !_following;
        _busy = false;
      });
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
        Text('@${widget.username}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 4,
                  mainAxisSpacing: 4,
                ),
                itemCount: snap.data!.docs.length,
                itemBuilder: (_, i) => MediaThumb(data: snap.data!.docs[i].data()),
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
  const FirestoreVideoCard({super.key, required this.doc, required this.onComment, required this.onLike, this.active = true});
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
    final snap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('savedVideos').doc(widget.doc.id).get();
    if (mounted) setState(() => _saved = snap.exists);
  }

  Future<void> _toggleSaved() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final ref = FirebaseFirestore.instance.collection('users').doc(uid).collection('savedVideos').doc(widget.doc.id);
    if (_saved) {
      await ref.delete();
    } else {
      await ref.set({'videoId': widget.doc.id, 'createdAt': FieldValue.serverTimestamp()});
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
        const ColoredBox(color: Colors.black, child: Center(child: Icon(Icons.play_circle, size: 80)))
      else if (isImage)
        applyFilter(data['filter'] as String? ?? 'none', Image.network(url, fit: BoxFit.cover))
      else
        RemoteVideo(
          url: url,
          active: widget.active,
          trimStartMs: (data['trimStartMs'] as num? ?? 0).toInt(),
          trimEndMs: (data['trimEndMs'] as num? ?? 0).toInt(),
          filter: data['filter'] as String? ?? 'none',
          volume: (data['originalVolume'] as num? ?? 1.0).toDouble(),
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
            child: Text('@${data['username'] ?? 'user'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
          const SizedBox(height: 5),
          Text(data['caption'] ?? ''),
          const SizedBox(height: 5),
          Text('♫ ${data['selectedSong'] ?? ''}', style: const TextStyle(fontSize: 12)),
        ]),
      ),
      Positioned(
        right: 10,
        bottom: 100,
        child: Column(children: [
          IconButton(
            icon: Icon(_liked ? Icons.favorite : Icons.favorite_border, color: _liked ? Colors.red : Colors.white, size: 38),
            onPressed: () async {
              final was = _liked;
              setState(() => _liked = !was);
              try {
                await widget.onLike(widget.doc.id, was);
              } catch (e) {
                if (mounted) {
                  setState(() => _liked = was);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تسجيل الإعجاب: $e')));
                }
              }
            },
          ),
          Text('$likes'),
          const SizedBox(height: 12),
          IconButton(
            icon: const Icon(Icons.comment, size: 34),
            onPressed: () => widget.onComment(widget.doc.id, data['commentsAllowed'] != false),
          ),
          Text('$comments'),
          const SizedBox(height: 12),
          const Icon(Icons.share, size: 34),
          const Text('مشاركة', style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          IconButton(
            onPressed: _toggleSaved,
            icon: Icon(_saved ? Icons.bookmark : Icons.bookmark_border, size: 32),
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
  static const MethodChannel _snapCameraChannel = MethodChannel('st_video/snap_camera');

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
    await Navigator.push(context, MaterialPageRoute(builder: (context) => const LiveStreamScreen()));
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
        builder: (context) => UploadPostScreen(mediaPath: pickedFile.path, isImage: _selectedMode == 'صورة'),
      ),
    );
  }

  Future<void> _openSnapCameraKit() async {
    try {
      final result = await _snapCameraChannel.invokeMethod<dynamic>('openCameraKitLenses');
      if (!mounted || result is! Map) return;
      final path = result['path']?.toString();
      if (path == null || path.isEmpty || !File(path).existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لم يتم العثور على الملف الناتج من كاميرا Snap')),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => UploadPostScreen(mediaPath: path)),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح فلاتر Snap: ${e.message ?? e.code}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر فتح فلاتر Snap: $e')),
      );
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              icon: const Icon(Icons.video_library),
              label: const Text('اختر فيديو من المعرض'),
              onPressed: () {
                setState(() => _selectedMode = 'فيديو');
                _pickFromGallery();
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
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
                      _selectedFilter = _selectedFilter == 'فلتر جمالي دافئ' ? 'فلتر نيون أزرق' : 'فلتر جمالي دافئ';
                    });
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تفعيل: $_selectedFilter ✨')));
                  },
                ),
                const Text('فلاتر الوجه', style: TextStyle(color: Colors.white, fontSize: 10)),
                const SizedBox(height: 18),
                IconButton(
                  icon: const Icon(Icons.auto_awesome, color: Colors.amber, size: 32),
                  onPressed: _openSnapCameraKit,
                  tooltip: 'فلاتر Snap الحقيقية',
                ),
                const Text('Snap Lenses', style: TextStyle(color: Colors.white, fontSize: 10)),
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
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
                      icon: const Icon(Icons.photo_library, color: Colors.white, size: 36),
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
                            Navigator.push(context, MaterialPageRoute(builder: (context) => UploadPostScreen(mediaPath: image.path, isImage: true)));
                          }
                        } else {
                          try {
                            if (_isRecording) {
                              final file = await _controller!.stopVideoRecording();
                              setState(() => _isRecording = false);
                              if (mounted) {
                                Navigator.push(context, MaterialPageRoute(builder: (context) => UploadPostScreen(mediaPath: file.path)));
                              }
                            } else {
                              await _controller!.startVideoRecording();
                              setState(() => _isRecording = true);
                            }
                          } catch (e) {
                            final picker = ImagePicker();
                            final picked = await picker.pickVideo(source: ImageSource.camera);
                            if (picked != null && mounted) {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => UploadPostScreen(mediaPath: picked.path)));
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
                                    : (_isRecording ? Icons.stop : Icons.fiber_manual_record),
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
  String _selectedSong = 'أغنية الحماس والترند 🎵'; // أغنية افتراضية تليق بالصورة/الفيديو تلقائياً
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
  int get _trimEndMs => _trim.end >= 0.999 ? 0 : (_duration.inMilliseconds * _trim.end).round();

  void _insertText(String textToInsert) {
    final currentText = _captionController.text;
    final selection = _captionController.selection;
    if (selection.start >= 0) {
      final newText = currentText.replaceRange(selection.start, selection.end, textToInsert);
      _captionController.text = newText;
      _captionController.selection = TextSelection.collapsed(offset: selection.start + textToInsert.length);
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
            final List<String> availableSongs = [
              'أغنية الحماس والترند 🎵',
              'ريمكس رقصة تيك توك 🔥',
              'موسيقى هادئة ورومانسية 🎸',
              'إيقاع سريع ورائع ⚡',
            ];
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('اختر الأغنية أو الموسيقى', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 150,
                    child: ListView.builder(
                      itemCount: availableSongs.length,
                      itemBuilder: (context, index) {
                        final song = availableSongs[index];
                        return ListTile(
                          title: Text(song, style: const TextStyle(color: Colors.white)),
                          trailing: _selectedSong == song ? const Icon(Icons.check, color: Colors.amber) : null,
                          onTap: () {
                            setState(() => _selectedSong = song);
                            setModalState(() {});
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(color: Colors.grey),
                  const Text('التحكم في مستويات الصوت 🎚️', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Text('الصوت الأصلي', style: TextStyle(color: Colors.white, fontSize: 12)),
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
                      const Text('الصوت المضاف', style: TextStyle(color: Colors.white, fontSize: 12)),
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سجل الدخول أولًا')));
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
      final contentType = isImage ? (ext == 'png' ? 'image/png' : 'image/jpeg') : 'video/mp4';
      final ref = FirebaseStorage.instance.ref('videos/${user.uid}/$id.$ext');
      final task = ref.putFile(file, SettableMetadata(contentType: contentType));
      task.snapshotEvents.listen((s) {
        if (mounted && s.totalBytes > 0) setState(() => _progress = s.bytesTransferred / s.totalBytes);
      });
      await task;
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('videos').doc(id).set({
        'id': id,
        'ownerId': user.uid,
        'username': AppData.userName,
        'caption': _captionController.text.trim().isEmpty ? 'منشور جديد 🔥' : _captionController.text.trim(),
        'commentsAllowed': _commentsAllowed,
        'selectedSong': _selectedSong,
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
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفع ونشر المحتوى بنجاح ✅'), backgroundColor: Colors.green));
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل رفع المحتوى (${e.code}): ${e.message ?? ''}')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل النشر: $e')));
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
                    ? applyFilter(_filter, Image.file(File(widget.mediaPath), fit: BoxFit.cover, width: double.infinity))
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
            const Text('الفلاتر 🎨', style: TextStyle(fontWeight: FontWeight.bold)),
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
              decoration: BoxDecoration(color: Colors.grey[850], borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.music_note, color: Colors.amber),
                  const SizedBox(width: 10),
                  Expanded(child: Text('الأغنية الحالية: $_selectedSong', style: const TextStyle(color: Colors.white))),
                  TextButton(onPressed: _openSongsPicker, child: const Text('تعديل الصوت', style: TextStyle(color: Colors.amber))),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[850]),
                  icon: const Icon(Icons.tag, color: Colors.amber),
                  label: const Text('هاشتاج #'),
                  onPressed: () => _insertText(' #ترند_تيك_توك '),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[850]),
                  icon: const Icon(Icons.alternate_email, color: Colors.blueAccent),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.all(14)),
              onPressed: _uploading ? null : _publishVideo,
              child: _uploading
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox(width: 20, height: 20, child: CircularProgressIndicator(value: _progress > 0 ? _progress : null, strokeWidth: 2.5)),
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
    if (uid == null) return const Scaffold(body: Center(child: Text('سجل الدخول أولًا')));
    final stream = FirebaseFirestore.instance.collection('users').doc(uid).collection('notifications').orderBy('createdAt', descending: true).snapshots();
    return Scaffold(
      appBar: AppBar(title: const Text('الإشعارات')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (_, snapshot) {
          if (snapshot.hasError) return Center(child: Text('خطأ: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return const Center(child: Text('لا توجد إشعارات بعد'));
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
    if (user == null) return const Scaffold(body: Center(child: Text('سجل الدخول أولًا')));
    final videos = FirebaseFirestore.instance.collection('videos').where('ownerId', isEqualTo: user.uid).snapshots();
    final profile = FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();
    return Scaffold(
      appBar: AppBar(
        title: const Text('حسابي'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'تعديل الملف الشخصي',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
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
                child: Text(data['bio'], textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
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
                  if (snap.hasError) return Center(child: Text('خطأ: ${snap.error}'));
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snap.data!.docs.toList()
                    ..sort((a, b) {
                      final ta = (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 1 << 50;
                      final tb = (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 1 << 50;
                      return tb.compareTo(ta);
                    });
                  if (docs.isEmpty) return const Center(child: Text('لم تنشر شيئًا بعد'));
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(5, 5, 5, 110),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
            ? applyFilter(data['filter'] as String? ?? 'none', Image.network(url, fit: BoxFit.cover, width: double.infinity, height: double.infinity))
            : Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.play_circle_fill, size: 36, color: Colors.white70),
                  Text(data['caption'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white54)),
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
      final d = (await FirebaseFirestore.instance.collection('users').doc(uid).get()).data();
      if (mounted && d != null) _bioController.text = (d['bio'] as String?) ?? '';
    } catch (_) {}
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
    if (picked != null) setState(() => _newPhoto = File(picked.path));
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    final name = _nameController.text.trim();
    if (user == null) return;
    if (name.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب اسمًا من حرفين على الأقل')));
      return;
    }
    setState(() => _saving = true);
    try {
      var photo = _photoUrl;
      if (_newPhoto != null) {
        final ref = FirebaseStorage.instance.ref('profile_images/${user.uid}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putFile(_newPhoto!, SettableMetadata(contentType: 'image/jpeg'));
        photo = await ref.getDownloadURL();
      }
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'displayName': name,
        'bio': _bioController.text.trim(),
        'phone': _phoneController.text.trim(),
        'photoUrl': photo,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      try {
        await user.updateDisplayName(name);
        if (photo.isNotEmpty) await user.updatePhotoURL(photo);
      } catch (e) {
        debugPrint('auth profile update: $e');
      }
      await AppData.loadProfile();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ التعديلات ✅'), backgroundColor: Colors.green));
    } on FirebaseException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ (${e.code}): ${e.message ?? ''}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
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
              CircleAvatar(radius: 56, backgroundImage: avatar, child: avatar == null ? const Icon(Icons.person, size: 60) : null),
              Positioned(
                bottom: 0,
                right: 0,
                child: CircleAvatar(radius: 18, backgroundColor: Colors.redAccent, child: const Icon(Icons.camera_alt, size: 18, color: Colors.white)),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'الاسم', prefixIcon: Icon(Icons.person))),
        const SizedBox(height: 14),
        TextField(controller: _bioController, maxLines: 2, maxLength: 120, decoration: const InputDecoration(labelText: 'نبذة عنك', prefixIcon: Icon(Icons.info_outline))),
        const SizedBox(height: 6),
        TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone))),
        const SizedBox(height: 24),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.all(14)),
          onPressed: _saving ? null : _save,
          child: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('حفظ التعديلات', style: TextStyle(fontSize: 16)),
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
    try {
      final result = await FirebaseFunctions.instance.httpsCallable('getWallet').call();
      if (mounted) setState(() => _wallet = Map<String, dynamic>.from(result.data as Map));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تحميل الرصيد: $e')));
    }
  }

  Future<void> _requestWithdrawal() async {
    final amount = int.tryParse(_amountController.text.trim());
    final destination = _destinationController.text.trim();
    if (amount == null || amount < minimumWithdrawalEgp || destination.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب مبلغًا لا يقل عن 50 جنيه وبيانات استلام صحيحة')));
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseFunctions.instance.httpsCallable('requestWithdrawal').call({
        'amountEgp': amount,
        'method': _method,
        'destination': destination,
      });
      _amountController.clear();
      _destinationController.clear();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال طلب السحب للمراجعة. التحويل يتم بعد اعتماد الإدارة.'), backgroundColor: Colors.green));
        _loadWallet();
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'فشل إنشاء طلب السحب')));
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
        padding: EdgeInsets.only(left: 16, right: 16, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
        child: StatefulBuilder(builder: (context, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('طلب سحب الأرباح', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('الحد الأدنى 50 جنيه. التحويل يتم يدويًا بعد مراجعة الإدارة.', style: TextStyle(color: Colors.white70)),
            TextField(controller: _amountController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'المبلغ بالجنيه المصري')),
            DropdownButtonFormField<String>(value: _method, items: const [
              DropdownMenuItem(value: 'instapay', child: Text('InstaPay')),
              DropdownMenuItem(value: 'wallet', child: Text('محفظة كاش')),
            ], onChanged: (value) => setSheetState(() => _method = value ?? 'instapay'), decoration: const InputDecoration(labelText: 'طريقة الاستلام')),
            TextField(controller: _destinationController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف أو عنوان InstaPay')),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _loading ? null : _requestWithdrawal, child: _loading ? const CircularProgressIndicator() : const Text('إرسال طلب السحب'))),
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
    return Scaffold(
      appBar: AppBar(title: const Text('الرصيد والأرباح'), actions: [IconButton(onPressed: _loadWallet, icon: const Icon(Icons.refresh))]),
      body: RefreshIndicator(
        onRefresh: _loadWallet,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            const Text('الرصيد المتاح', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Text('$available عملة', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.amber)),
            Text('${(available / coinsPerEgp).toStringAsFixed(2)} جنيه مصري', style: const TextStyle(color: Colors.greenAccent)),
          ]))),
          const SizedBox(height: 12),
          ListTile(leading: const Icon(Icons.trending_up, color: Colors.greenAccent), title: const Text('إجمالي الأرباح'), subtitle: Text('$earned عملة')),
          ListTile(leading: const Icon(Icons.lock_clock, color: Colors.orangeAccent), title: const Text('قيد المراجعة'), subtitle: Text('$pending عملة')),
          const Divider(),
          const ListTile(leading: Icon(Icons.live_tv, color: Colors.redAccent), title: Text('أرباح البث'), subtitle: Text('المنصة تحصل على 20% وصاحب البث يحصل على 80% من قيمة الهدايا.')),
          const ListTile(leading: Icon(Icons.ondemand_video, color: Colors.blueAccent), title: Text('أرباح الإعلانات'), subtitle: Text('تُضاف فقط من إعلانات موثقة بعد وصول بيانات شبكة الإعلانات، وليس لمجرد فتح التطبيق.')),
          const SizedBox(height: 12),
          ElevatedButton.icon(onPressed: available >= minimumWithdrawalEgp * coinsPerEgp ? _showWithdrawalForm : null, icon: const Icon(Icons.account_balance_wallet), label: const Text('طلب سحب الأرباح')),
          const SizedBox(height: 8),
          const Text('100 عملة = 50 جنيه. الحد الأدنى للسحب 50 جنيه.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
        ]),
      ),
    );
  }
}

// 7. صفحة الإعدادات (المعلومات الشخصية، الرصيد، وتسجيل الخروج في الأسفل)
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات والخصوصية')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.person_outline, color: Colors.white),
            title: const Text('المعلومات الشخصية'),
            subtitle: Text('الاسم: ${AppData.userName}\nالرقم: ${AppData.userPhone.isEmpty ? '—' : AppData.userPhone}\nالبريد: ${AppData.userEmail}'),
            isThreeLine: true,
            trailing: const Icon(Icons.edit, size: 18, color: Colors.grey),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EditProfileScreen())),
          ),
          const Divider(color: Colors.grey),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet, color: Colors.amber),
            title: const Text('الرصيد والأرباح'),
            subtitle: const Text('الهدايا، أرباح الإعلانات، وطلبات السحب'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen())),
          ),
          const Divider(color: Colors.grey),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.all(12)),
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text('تسجيل الخروج من الحساب', style: TextStyle(color: Colors.white, fontSize: 16)),
              onPressed: () async {
                AppData.isLoggedIn = false;
                try {
                  await GoogleSignIn().signOut();
                } catch (_) {}
                await FirebaseAuth.instance.signOut();
                if (!context.mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const AuthScreen()),
                  (route) => false,
                );
              },
            ),
          ),
        ],
      ),
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
      await [Permission.camera, Permission.microphone].request();
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
        token: '007eJxTYDjX7Rn4LXbf/gyxPzbTHnRw/tnsInJ+1i/hBCb/ac1tSm4KDEmWppYpFoYmaZapBibJ5gaJiebJpimGFgYWSUkmxiZpEp+2ZDUEMjK42DEyMTJAIIjPwlCSWlzCwAAAWvwe1g==',
        channelId: 'test',
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
      body = Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error!, textAlign: TextAlign.center)));
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
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اكتشف الترندات')),
      body: GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.5,
        ),
        itemCount: 6,
        itemBuilder: (context, index) => Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.primaries[(index * 3) % Colors.primaries.length].withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.35),
              ],
            ),
            border: Border.all(color: Colors.white24),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Text(
              '#هاشتاج_الترند_${index + 1} 🔥',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }
}
