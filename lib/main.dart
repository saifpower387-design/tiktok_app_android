import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:video_player/video_player.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:io';

// Agora App ID الخاص بالبث المباشر
const agoraAppId = 'b959d814f9e04c70aa7c5d1808bb434f';

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
  static int userBalance = 0;
  static List<CameraDescription> cameras = [];
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  AppData.isLoggedIn = FirebaseAuth.instance.currentUser != null;
  if (FirebaseAuth.instance.currentUser != null) {
    AppData.userEmail = FirebaseAuth.instance.currentUser!.email ?? AppData.userEmail;
    AppData.userName = FirebaseAuth.instance.currentUser!.displayName ?? AppData.userName;
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
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.redAccent,
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
      final googleSignIn = GoogleSignIn(
        serverClientId: '67126189193-akc65ebuqfnm9988212nbt47bqk061ul.apps.googleusercontent.com',
      );
      // تسجيل الخروج من جلسة Google القديمة حتى يظهر اختيار الحسابات.
      await googleSignIn.signOut();
      final account = await googleSignIn.signIn().timeout(const Duration(seconds: 10));
      if (account == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final auth = await account.authentication.timeout(const Duration(seconds: 10));
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      final result = await FirebaseAuth.instance
          .signInWithCredential(credential)
          .timeout(const Duration(seconds: 10));
      final user = result.user!;
      if (!mounted) return;
      AppData.isLoggedIn = true;
      AppData.userEmail = user.email ?? '';
      AppData.userName = user.displayName ?? user.email?.split('@').first ?? 'مستخدم';
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName ?? 'مستخدم جديد',
          'photoUrl': user.photoURL,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
      } catch (_) {
        // نجاح تسجيل Google لا يتوقف على حفظ بيانات الملف الشخصي.
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
        final result = await FirebaseFirestore.instance
            .collection('users')
            .where('username', isEqualTo: identifier.toLowerCase())
            .limit(1)
            .get();
        if (result.docs.isEmpty) {
          throw FirebaseAuthException(code: 'user-not-found', message: 'اسم المستخدم غير موجود');
        }
        email = result.docs.first.data()['email'] as String? ?? '';
        if (email.isEmpty) {
          throw FirebaseAuthException(code: 'invalid-user-data', message: 'بيانات المستخدم غير مكتملة');
        }
      }
      if (!_isLogin) {
        final existing = await FirebaseFirestore.instance
            .collection('users')
            .where('username', isEqualTo: username)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) {
          throw FirebaseAuthException(code: 'username-already-in-use', message: 'اسم المستخدم مستخدم بالفعل');
        }
      }
      final result = _isLogin
          ? await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password)
          : await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      final user = result.user!;
      AppData.isLoggedIn = true;
      AppData.userEmail = user.email ?? email;
      AppData.userName = _isLogin ? identifier : username;
      final userData = <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'displayName': _isLogin ? user.displayName ?? email.split('@').first : username,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (!_isLogin) userData['username'] = username;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(userData, SetOptions(merge: true));
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
  final List<Widget> _screens = [
    const VideoFeedScreen(),
    const DiscoverScreen(),
    const CameraStudioScreen(),
    const InboxScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black,
        selectedItemColor: Colors.redAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'اكتشف'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box, size: 38, color: Colors.redAccent), label: 'تصوير'),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: 'الرسائل'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'حسابي'),
        ],
      ),
    );
  }
}

class RemoteVideo extends StatefulWidget {
  final String url;
  const RemoteVideo({super.key, required this.url});
  @override
  State<RemoteVideo> createState() => _RemoteVideoState();
}

class _RemoteVideoState extends State<RemoteVideo> {
  late final VideoPlayerController _controller;
  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) return const Center(child: CircularProgressIndicator());
    return GestureDetector(
      onTap: () {
        setState(() {
          _controller.value.isPlaying ? _controller.pause() : _controller.play();
        });
      },
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller.value.size.width,
          height: _controller.value.size.height,
          child: VideoPlayer(_controller),
        ),
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
    final ownerId = (await videoRef.get()).data()?['ownerId'];
    if (!liked && ownerId != null && ownerId != user.uid) {
      await FirebaseFirestore.instance.collection('users').doc(ownerId).collection('notifications').add({
        'title': 'إعجاب جديد',
        'body': '${user.displayName ?? 'مستخدم'} أعجب بمنشورك',
        'type': 'like',
        'createdAt': FieldValue.serverTimestamp(),
      });
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
        'username': user.displayName ?? user.email?.split('@').first ?? 'مستخدم',
        'text': value,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(videoRef, {'commentsCount': current + 1});
    });
    final ownerId = (await videoRef.get()).data()?['ownerId'];
    if (ownerId != null && ownerId != user.uid) {
      await FirebaseFirestore.instance.collection('users').doc(ownerId).collection('notifications').add({
        'title': 'تعليق جديد',
        'body': '${user.displayName ?? 'مستخدم'} كتب تعليقًا على منشورك',
        'type': 'comment',
        'createdAt': FieldValue.serverTimestamp(),
      });
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
            return PageView.builder(
              scrollDirection: Axis.vertical,
              itemCount: docs.length,
              itemBuilder: (_, index) => FirestoreVideoCard(
                doc: docs[index],
                onComment: _showCommentsSheet,
                onLike: _toggleLike,
              ),
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
        'body': '${me.displayName ?? 'مستخدم'} بدأ متابعتك',
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
        .orderBy('createdAt', descending: true)
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
                itemBuilder: (_, i) {
                  final u = snap.data!.docs[i].data()['downloadUrl'] as String? ?? '';
                  return u.isEmpty
                      ? const ColoredBox(color: Colors.grey)
                      : Image.network(u, fit: BoxFit.cover);
                },
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
  const FirestoreVideoCard({super.key, required this.doc, required this.onComment, required this.onLike});
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
        Image.network(url, fit: BoxFit.cover)
      else
        RemoteVideo(url: url),
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
        bottom: 80,
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
        bottom: 70,
        child: Column(children: [
          IconButton(
            icon: Icon(_liked ? Icons.favorite : Icons.favorite_border, color: _liked ? Colors.red : Colors.white, size: 38),
            onPressed: () async {
              await widget.onLike(widget.doc.id, _liked);
              if (mounted) setState(() => _liked = !_liked);
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

  final List<String> _cameraFilters = const [
    'بدون فلتر',
    'طبيعي',
    'دافئ',
    'بارد',
    'أبيض وأسود',
    'سيبيا',
    'ساطع',
    'نيون',
    'سينمائي',
    'فنتج',
    'حيوي',
    'باهت',
    'غروب',
    'أخضر سينمائي',
    'عكس الألوان',
  ];

  ColorFilter? _cameraColorFilter(String filter) {
    switch (filter) {
      case 'أبيض وأسود':
        return const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case 'سيبيا':
        return const ColorFilter.matrix(<double>[
          0.393, 0.769, 0.189, 0, 0,
          0.349, 0.686, 0.168, 0, 0,
          0.272, 0.534, 0.131, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case 'دافئ':
        return const ColorFilter.matrix(<double>[
          1.08, 0, 0, 0, 8,
          0, 1.01, 0, 0, 2,
          0, 0, 0.90, 0, -4,
          0, 0, 0, 1, 0,
        ]);
      case 'بارد':
        return const ColorFilter.matrix(<double>[
          0.92, 0, 0, 0, 0,
          0, 1.02, 0, 0, 2,
          0, 0, 1.12, 0, 10,
          0, 0, 0, 1, 0,
        ]);
      case 'ساطع':
        return const ColorFilter.matrix(<double>[
          1.18, 0, 0, 0, 8,
          0, 1.18, 0, 0, 8,
          0, 0, 1.18, 0, 8,
          0, 0, 0, 1, 0,
        ]);
      case 'نيون':
        return const ColorFilter.matrix(<double>[
          1.18, 0, 0, 0, 0,
          0, 0.92, 0, 0, 8,
          0, 0, 1.25, 0, 15,
          0, 0, 0, 1, 0,
        ]);
      case 'سينمائي':
        return const ColorFilter.matrix(<double>[
          1.15, 0, 0, 0, -8,
          0, 1.05, 0, 0, -4,
          0, 0, 0.90, 0, 2,
          0, 0, 0, 1, 0,
        ]);
      case 'فنتج':
        return const ColorFilter.matrix(<double>[
          0.90, 0.05, 0.02, 0, 10,
          0.02, 0.82, 0.04, 0, 6,
          0.01, 0.04, 0.70, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case 'حيوي':
        return const ColorFilter.matrix(<double>[
          1.30, -0.12, -0.12, 0, 0,
          -0.08, 1.25, -0.08, 0, 0,
          -0.08, -0.08, 1.30, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case 'باهت':
        return const ColorFilter.matrix(<double>[
          0.82, 0.08, 0.08, 0, 18,
          0.08, 0.82, 0.08, 0, 18,
          0.08, 0.08, 0.82, 0, 18,
          0, 0, 0, 1, 0,
        ]);
      case 'غروب':
        return const ColorFilter.matrix(<double>[
          1.20, 0.05, 0, 0, 12,
          0, 0.92, 0.02, 0, 0,
          0, 0.02, 0.78, 0, -2,
          0, 0, 0, 1, 0,
        ]);
      case 'أخضر سينمائي':
        return const ColorFilter.matrix(<double>[
          0.88, 0.08, 0.02, 0, 0,
          0.04, 1.12, 0.04, 0, 4,
          0.02, 0.12, 0.82, 0, 0,
          0, 0, 0, 1, 0,
        ]);
      case 'عكس الألوان':
        return const ColorFilter.matrix(<double>[
          -1, 0, 0, 0, 255,
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]);
      default:
        return null;
    }
  }

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
        builder: (context) => UploadPostScreen(mediaPath: pickedFile.path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized || _controller == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('الكاميرا الحية')),
        body: Center(
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            icon: const Icon(Icons.photo_library),
            label: const Text('اختر فيديو من المعرض'),
            onPressed: _pickFromGallery,
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_cameraColorFilter(_selectedFilter) == null)
            CameraPreview(_controller!)
          else
            ColorFiltered(
              colorFilter: _cameraColorFilter(_selectedFilter)!,
              child: CameraPreview(_controller!),
            ),
          // شريط فلاتر مباشر مثل تطبيقات الفيديو القصيرة
          Positioned(
            top: 50,
            left: 10,
            right: 10,
            child: SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _cameraFilters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, index) {
                  final filter = _cameraFilters[index];
                  final selected = filter == _selectedFilter;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedFilter = filter),
                    child: Column(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? Colors.amber : Colors.black54,
                          border: Border.all(color: selected ? Colors.white : Colors.white54, width: 2),
                        ),
                        child: Icon(filter == 'أبيض وأسود' ? Icons.contrast : Icons.auto_awesome, color: selected ? Colors.black : Colors.white),
                      ),
                      const SizedBox(height: 3),
                      Text(filter, style: const TextStyle(color: Colors.white, fontSize: 10)),
                    ]),
                  );
                },
              ),
            ),
          ),
          // زر التقاط الصورة / الفيديو / البث السفلي مع خيار المعرض والوضع
          Positioned(
            bottom: 30,
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
                            Navigator.push(context, MaterialPageRoute(builder: (context) => UploadPostScreen(mediaPath: image.path)));
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
  const UploadPostScreen({super.key, required this.mediaPath});

  @override
  State<UploadPostScreen> createState() => _UploadPostScreenState();
}

class _UploadPostScreenState extends State<UploadPostScreen> {
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _songSearchController = TextEditingController();
  VideoPlayerController? _previewController;
  bool _previewReady = false;
  bool _isPublishing = false;
  bool _commentsAllowed = true;
  String _selectedSong = 'أغنية الحماس والترند 🎵'; // أغنية افتراضية تليق بالصورة/الفيديو تلقائياً
  double _originalSoundVolume = 0.8;
  double _addedSongVolume = 0.5;

  final List<String> _availableSongs = const [
    'أغنية الحماس والترند 🎵',
    'ريمكس رقصة تيك توك 🔥',
    'موسيقى هادئة ورومانسية 🎸',
    'إيقاع سريع ورائع ⚡',
    'موسيقى سينمائية ملهمة 🎬',
    'ترند الصيف العربي ☀️',
    'موسيقى سفر ومغامرة 🌍',
    'إيقاع شعبي سريع 🥁',
  ];

  @override
  void initState() {
    super.initState();
    final isImage = widget.mediaPath.toLowerCase().endsWith('.jpg') ||
        widget.mediaPath.toLowerCase().endsWith('.jpeg') ||
        widget.mediaPath.toLowerCase().endsWith('.png');
    if (!isImage) {
      _previewController = VideoPlayerController.file(File(widget.mediaPath))
        ..initialize().then((_) {
          if (mounted) setState(() => _previewReady = true);
        });
    }
  }

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
            final search = _songSearchController.text.trim().toLowerCase();
            final songs = _availableSongs.where((song) => song.toLowerCase().contains(search)).toList();
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('اختر الأغنية أو الموسيقى', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _songSearchController,
                    onChanged: (_) => setModalState(() {}),
                    decoration: const InputDecoration(hintText: 'ابحث عن أغنية...', prefixIcon: Icon(Icons.search), filled: true),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 190,
                    child: ListView.builder(
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        return ListTile(
                          title: Text(song, style: const TextStyle(color: Colors.white)),
                          trailing: _selectedSong == song ? const Icon(Icons.check, color: Colors.amber) : null,
                          onTap: () {
                            setState(() => _selectedSong = song);
                            Navigator.pop(context);
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
    if (_isPublishing) return;
    setState(() => _isPublishing = true);
    try {
      final mediaFile = File(widget.mediaPath);
      if (!await mediaFile.exists()) {
        throw Exception('ملف الفيديو غير موجود على الهاتف، اختر الفيديو مرة أخرى');
      }
      final fileSize = await mediaFile.length();
      if (fileSize == 0) {
        throw Exception('ملف الفيديو فارغ أو تالف');
      }
      final id = FirebaseFirestore.instance.collection('videos').doc().id;
      final isImage = widget.mediaPath.toLowerCase().endsWith('.jpg') ||
          widget.mediaPath.toLowerCase().endsWith('.jpeg') ||
          widget.mediaPath.toLowerCase().endsWith('.png');
      final ext = isImage ? 'jpg' : 'mp4';
      final ref = FirebaseStorage.instance.ref('videos/${user.uid}/$id.$ext');
      await ref.putFile(
        mediaFile,
        SettableMetadata(contentType: isImage ? 'image/jpeg' : 'video/mp4'),
      ).timeout(const Duration(minutes: 2));
      final url = await ref.getDownloadURL().timeout(const Duration(seconds: 10));
      await FirebaseFirestore.instance.collection('videos').doc(id).set({
        'id': id,
        'ownerId': user.uid,
        'username': user.displayName ?? user.email?.split('@').first ?? 'saif_creator',
        'caption': _captionController.text.trim().isEmpty ? 'منشور جديد 🔥' : _captionController.text.trim(),
        'commentsAllowed': _commentsAllowed,
        'selectedSong': _selectedSong,
        'downloadUrl': url,
        'mediaType': isImage ? 'image' : 'video',
        'createdAt': FieldValue.serverTimestamp(),
        'likesCount': 0,
        'commentsCount': 0,
      }).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفع ونشر المحتوى على Firebase بنجاح'), backgroundColor: Colors.green));
      Navigator.pop(context);
    } on FirebaseException catch (e) {
      final message = switch (e.code) {
        'storage/unauthorized' => 'ليس لديك صلاحية رفع الفيديو. راجع Firebase Storage Rules.',
        'storage/canceled' => 'تم إلغاء رفع الفيديو',
        'storage/quota-exceeded' => 'تم تجاوز مساحة Firebase Storage المتاحة',
        'storage/unauthenticated' => 'انتهت جلسة الدخول، سجّل الدخول مرة أخرى',
        'permission-denied' => 'قواعد Firestore تمنع نشر الفيديو',
        _ => 'فشل رفع الفيديو: ${e.message ?? e.code}',
      };
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل النشر: $e')));
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _songSearchController.dispose();
    _previewController?.dispose();
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
            Container(
              height: 360,
              width: double.infinity,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(14)),
              child: widget.mediaPath.toLowerCase().endsWith('.jpg') ||
                      widget.mediaPath.toLowerCase().endsWith('.jpeg') ||
                      widget.mediaPath.toLowerCase().endsWith('.png')
                  ? Image.file(File(widget.mediaPath), fit: BoxFit.contain)
                  : _previewReady && _previewController != null
                      ? GestureDetector(
                          onTap: () {
                            setState(() {
                              if (_previewController!.value.isPlaying) {
                                _previewController!.pause();
                              } else {
                                _previewController!.play();
                              }
                            });
                          },
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: _previewController!.value.aspectRatio,
                              child: VideoPlayer(_previewController!),
                            ),
                          ),
                        )
                      : const Center(child: CircularProgressIndicator()),
            ),
            const SizedBox(height: 14),
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
              onPressed: _isPublishing ? null : _publishVideo,
              child: _isPublishing
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('نشر الآن 🚀', style: TextStyle(fontSize: 16)),
            ),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('الملف الشخصي'),
        actions: [
          IconButton(icon: const Icon(Icons.qr_code_2), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileQrScreen()))),
          IconButton(icon: const Icon(Icons.menu), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
        builder: (_, snap) {
          final data = snap.data?.data() ?? {};
          return DefaultTabController(
            length: 4,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                        _profileStat('المتابعون', data['followersCount'] ?? 0),
                        _profileStat('أتابعهم', data['followingCount'] ?? 0),
                      ]),
                    ),
                    const SizedBox(width: 18),
                    Column(children: [
                      CircleAvatar(radius: 43, backgroundImage: user.photoURL == null ? null : NetworkImage(user.photoURL!), child: user.photoURL == null ? const Icon(Icons.person, size: 50) : null),
                      const SizedBox(height: 7),
                      Text(data['displayName'] ?? user.displayName ?? user.email ?? 'مستخدم', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('@${data['username'] ?? user.email?.split('@').first ?? 'user'}', style: const TextStyle(color: Colors.grey)),
                    ]),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileEditScreen())), icon: const Icon(Icons.edit), label: const Text('تعديل الملف الشخصي'))),
              ),
              const TabBar(tabs: [Tab(icon: Icon(Icons.grid_on), text: 'عام'), Tab(icon: Icon(Icons.lock_outline), text: 'خاص'), Tab(icon: Icon(Icons.favorite_border), text: 'أعجبني'), Tab(icon: Icon(Icons.repeat), text: 'إعادة نشر')]),
              Expanded(child: TabBarView(children: [
                _ProfileVideoGrid(userId: user.uid, mode: 'public'),
                _ProfileVideoGrid(userId: user.uid, mode: 'private'),
                _ProfileVideoGrid(userId: user.uid, mode: 'liked'),
                _ProfileVideoGrid(userId: user.uid, mode: 'reposted'),
              ])),
            ]),
          );
        },
      ),
    );
  }

  Widget _profileStat(String label, dynamic value) => Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Column(children: [Text('$value', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)), Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12))]));
}

class _ProfileVideoGrid extends StatelessWidget {
  final String userId;
  final String mode;
  const _ProfileVideoGrid({required this.userId, required this.mode});
  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('videos').where('ownerId', isEqualTo: userId).orderBy('createdAt', descending: true);
    if (mode == 'private') query = query.where('visibility', isEqualTo: 'private');
    if (mode == 'public') query = query.where('visibility', isEqualTo: 'public');
    if (mode == 'liked' || mode == 'reposted') return Center(child: Text(mode == 'liked' ? 'الفيديوهات التي أعجبت بها ستظهر هنا' : 'الفيديوهات المعاد نشرها ستظهر هنا', style: const TextStyle(color: Colors.grey)));
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(stream: query.snapshots(), builder: (_, snap) {
      if (snap.hasError) return Center(child: Text('تعذر تحميل الفيديوهات: ${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
      final docs = snap.data!.docs;
      if (docs.isEmpty) return Center(child: Text(mode == 'private' ? 'لا توجد فيديوهات خاصة' : 'لا توجد فيديوهات عامة'));
      return GridView.builder(padding: const EdgeInsets.all(4), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 3, mainAxisSpacing: 3), itemCount: docs.length, itemBuilder: (_, i) { final url=docs[i].data()['downloadUrl'] as String? ?? ''; return url.isEmpty ? const ColoredBox(color: Colors.grey) : Image.network(url, fit: BoxFit.cover); });
    });
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات والخصوصية')),
      body: ListView(children: [
        const _SettingsHeader(title: 'الحساب'),
        ListTile(leading: const Icon(Icons.person_outline), title: const Text('المعلومات الشخصية'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonalInfoScreen()))),
        ListTile(leading: const Icon(Icons.account_balance_wallet, color: Colors.amber), title: const Text('الرصيد والأرباح'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BalanceScreen()))),
        ListTile(leading: const Icon(Icons.swap_horiz), title: const Text('تبديل الحساب'), trailing: const Icon(Icons.chevron_left), onTap: () => _showInfo(context, 'تبديل الحساب', 'يمكنك إضافة حساب آخر وتسجيل الدخول به من هنا.')),
        const _SettingsHeader(title: 'الأمان والخصوصية'),
        ListTile(leading: const Icon(Icons.lock_outline), title: const Text('كلمة المرور'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ChangePasswordScreen()))),
        ListTile(leading: const Icon(Icons.security), title: const Text('الأمان والأذونات'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityScreen()))),
        ListTile(leading: const Icon(Icons.block), title: const Text('الحسابات المحظورة'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BlockedAccountsScreen()))),
        ListTile(leading: const Icon(Icons.circle, color: Colors.green, size: 16), title: const Text('حالة الحساب والنشاط'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountStatusScreen()))),
        const _SettingsHeader(title: 'المساعدة'),
        ListTile(leading: const Icon(Icons.help_outline), title: const Text('مركز المساعدة والإبلاغ'), trailing: const Icon(Icons.chevron_left), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpCenterScreen()))),
        const SizedBox(height: 25),
        Padding(padding: const EdgeInsets.all(16), child: OutlinedButton.icon(icon: const Icon(Icons.logout, color: Colors.red), label: const Text('تسجيل الخروج', style: TextStyle(color: Colors.red)), onPressed: () async { await GoogleSignIn(serverClientId: '67126189193-akc65ebuqfnm9988212nbt47bqk061ul.apps.googleusercontent.com').signOut(); await FirebaseAuth.instance.signOut(); if (context.mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false); })),
      ]),
    );
  }
  static void _showInfo(BuildContext context, String title, String text) => showDialog(context: context, builder: (_) => AlertDialog(title: Text(title), content: Text(text), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسنًا'))]));
}

class _SettingsHeader extends StatelessWidget { final String title; const _SettingsHeader({required this.title}); @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 6), child: Text(title, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold))); }

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});
  @override State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _nameController = TextEditingController();
  XFile? _selectedImage;
  bool _busy = false;
  DateTime? _lastNameChange;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameController.text = user?.displayName ?? AppData.userName;
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final value = snap.data()?['lastNameChangeAt'];
    if (value is Timestamp && mounted) setState(() => _lastNameChange = value.toDate());
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null && mounted) setState(() => _selectedImage = picked);
  }

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _busy) return;
    final newName = _nameController.text.trim();
    if (newName.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اكتب اسمًا صحيحًا')));
      return;
    }
    final changedName = newName != (user.displayName ?? AppData.userName);
    if (changedName && _lastNameChange != null && DateTime.now().difference(_lastNameChange!).inDays < 7) {
      final days = 7 - DateTime.now().difference(_lastNameChange!).inDays;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('لا يمكن تغيير الاسم الآن. انتظر $days أيام أخرى.')));
      return;
    }
    setState(() => _busy = true);
    try {
      String? photoUrl = user.photoURL;
      if (_selectedImage != null) {
        final ref = FirebaseStorage.instance.ref('users/${user.uid}/profile.jpg');
        await ref.putFile(File(_selectedImage!.path), SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
        await user.updatePhotoURL(photoUrl);
      }
      if (changedName) {
        await user.updateDisplayName(newName);
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({'displayName': newName, 'lastNameChangeAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
      }
      if (photoUrl != null) await FirebaseFirestore.instance.collection('users').doc(user.uid).set({'photoUrl': photoUrl}, SetOptions(merge: true));
      AppData.userName = newName;
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ تعديل الملف الشخصي'))); Navigator.pop(context); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر حفظ التعديل: $e')));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(appBar: AppBar(title: const Text('تعديل الملف الشخصي')), body: ListView(padding: const EdgeInsets.all(20), children: [
      Center(child: GestureDetector(onTap: _pickImage, child: Stack(alignment: Alignment.bottomRight, children: [CircleAvatar(radius: 58, backgroundImage: _selectedImage != null ? FileImage(File(_selectedImage!.path)) : (user?.photoURL == null ? null : NetworkImage(user!.photoURL!)) as ImageProvider?, child: user?.photoURL == null && _selectedImage == null ? const Icon(Icons.person, size: 60) : null), const CircleAvatar(radius: 18, child: Icon(Icons.camera_alt, size: 18))]))),
      const SizedBox(height: 10), const Center(child: Text('اضغط على الصورة لتغييرها', style: TextStyle(color: Colors.grey))), const SizedBox(height: 25),
      TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'الاسم الظاهر', prefixIcon: Icon(Icons.person), filled: true)),
      const SizedBox(height: 10), const Text('تحذير: يمكنك تغيير الاسم مرة واحدة كل 7 أيام.', style: TextStyle(color: Colors.amber)),
      const SizedBox(height: 25), ElevatedButton(onPressed: _busy ? null : _save, child: _busy ? const CircularProgressIndicator() : const Text('حفظ التعديلات')),
    ]));
  }
  @override void dispose() { _nameController.dispose(); super.dispose(); }
}

class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});
  @override State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  bool _busy = false;
  String? _verificationId;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _emailController.text = user?.email ?? '';
    _phoneController.text = user?.phoneNumber ?? '';
  }

  Future<void> _linkGoogle() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final account = await GoogleSignIn(serverClientId: '67126189193-akc65ebuqfnm9988212nbt47bqk061ul.apps.googleusercontent.com').signIn();
      if (account == null) return;
      final auth = await account.authentication;
      await user.linkWithCredential(GoogleAuthProvider.credential(accessToken: auth.accessToken, idToken: auth.idToken));
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم ربط حساب Google بنجاح')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر ربط Google: $e')));
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _saveEmail() async {
    final email = _emailController.text.trim();
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || email.isEmpty) return;
    try {
      await user.verifyBeforeUpdateEmail(email);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال رابط تأكيد إلى البريد الجديد')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر تغيير البريد: $e')));
    }
  }

  Future<void> _unlink(String providerId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.providerData.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يمكن فصل وسيلة الدخول الوحيدة')));
      return;
    }
    try {
      await user.unlink(providerId);
      if (mounted) { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم فصل وسيلة الدخول'))); }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر الفصل: $e')));
    }
  }

  Future<void> _startPhoneLink() async {
    final user = FirebaseAuth.instance.currentUser;
    final phone = _phoneController.text.trim();
    if (user == null || phone.isEmpty) return;
    setState(() => _busy = true);
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (credential) async {
        try { await user.linkWithCredential(credential); if (mounted) setState(() => _busy = false); }
        catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر ربط الهاتف: $e'))); }
      },
      verificationFailed: (e) {
        if (mounted) { setState(() => _busy = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إرسال رمز SMS: ${e.message ?? e.code}'))); }
      },
      codeSent: (id, _) { _verificationId = id; if (mounted) { setState(() => _busy = false); _showSmsDialog(); } },
      codeAutoRetrievalTimeout: (id) => _verificationId = id,
    );
  }

  Future<void> _showSmsDialog() async {
    _smsCodeController.clear();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('رمز التحقق'),
        content: TextField(controller: _smsCodeController, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'أدخل رمز SMS')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () async {
            final id = _verificationId;
            final code = _smsCodeController.text.trim();
            final user = FirebaseAuth.instance.currentUser;
            if (id == null || code.isEmpty || user == null) return;
            try {
              await user.linkWithCredential(PhoneAuthProvider.credential(verificationId: id, smsCode: code));
              if (dialogContext.mounted) Navigator.pop(dialogContext);
              if (mounted) { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم ربط رقم الهاتف بنجاح'))); }
            } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('رمز غير صحيح: $e'))); }
          }, child: const Text('تأكيد')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final providers = user?.providerData.map((p) => p.providerId).toSet() ?? <String>{};
    return Scaffold(appBar: AppBar(title: const Text('المعلومات الشخصية')), body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('بيانات الاتصال والربط', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 15),
      TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email), filled: true)),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: _busy ? null : _saveEmail, child: const Text('حفظ البريد الإلكتروني')),
      const SizedBox(height: 15),
      TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'رقم الهاتف بصيغة دولية مثل +2010...', prefixIcon: Icon(Icons.phone), filled: true)),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: _busy ? null : _startPhoneLink, icon: const Icon(Icons.sms), label: const Text('إرسال رمز وربط الهاتف')),
      const Divider(height: 35),
      ListTile(leading: const Icon(Icons.account_circle), title: const Text('Google'), subtitle: Text(providers.contains('google.com') ? 'مرتبط بهذا الحساب' : 'غير مرتبط'), trailing: providers.contains('google.com') ? TextButton(onPressed: providers.length > 1 ? () => _unlink('google.com') : null, child: const Text('فصل')) : ElevatedButton(onPressed: _busy ? null : _linkGoogle, child: const Text('ربط'))),
      ListTile(leading: const Icon(Icons.phone), title: const Text('الهاتف'), subtitle: Text(providers.contains('phone') ? 'مرتبط بهذا الحساب' : 'غير مرتبط'), trailing: providers.contains('phone') ? TextButton(onPressed: providers.length > 1 ? () => _unlink('phone') : null, child: const Text('فصل')) : null),
      const SizedBox(height: 15),
      const Text('تحذير: لا يمكن إزالة وسيلة الدخول الوحيدة حتى لا تفقد الوصول إلى الحساب.', style: TextStyle(color: Colors.grey)),
    ]));
  }

  @override void dispose() { _emailController.dispose(); _phoneController.dispose(); _smsCodeController.dispose(); super.dispose(); }
}

class BalanceScreen extends StatelessWidget { const BalanceScreen({super.key}); @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('الرصيد والأرباح')), body: ListView(padding: const EdgeInsets.all(20), children: [Card(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [const Icon(Icons.account_balance_wallet, color: Colors.amber, size: 55), const SizedBox(height: 12), const Text('الرصيد الحالي', style: TextStyle(color: Colors.grey)), Text('${AppData.userBalance} عملة', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold))]))), const SizedBox(height: 20), const ListTile(leading: Icon(Icons.info_outline), title: Text('الأرباح'), subtitle: Text('لا توجد أرباح مسجلة حاليًا. لن يتم عرض رصيد وهمي.')), const ListTile(leading: Icon(Icons.history), title: Text('سجل الأرباح'), subtitle: Text('لا توجد عمليات مسجلة حتى الآن.'))])); }

class ChangePasswordScreen extends StatefulWidget { const ChangePasswordScreen({super.key}); @override State<ChangePasswordScreen> createState()=>_ChangePasswordScreenState(); }
class _ChangePasswordScreenState extends State<ChangePasswordScreen> { final c=TextEditingController(); bool busy=false; @override Widget build(BuildContext context)=>Scaffold(appBar: AppBar(title: const Text('تغيير كلمة المرور')), body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [TextField(controller:c, obscureText:true, decoration: const InputDecoration(labelText:'كلمة المرور الجديدة')), const SizedBox(height:20), ElevatedButton(onPressed: busy ? null : () async { if(c.text.length<6)return; setState(()=>busy=true); try { await FirebaseAuth.instance.currentUser?.updatePassword(c.text); if(context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير كلمة المرور'))); Navigator.pop(context); } } catch(e) { if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر التغيير: $e'))); } finally { if(mounted)setState(()=>busy=false); } }, child: const Text('حفظ'))]))); @override void dispose(){c.dispose();super.dispose();} }

class SecurityScreen extends StatefulWidget { const SecurityScreen({super.key}); @override State<SecurityScreen> createState()=>_SecurityScreenState(); }
class _SecurityScreenState extends State<SecurityScreen> { bool alerts=true, twoFactor=false; @override Widget build(BuildContext context)=>Scaffold(appBar: AppBar(title: const Text('الأمان والأذونات')), body: ListView(children: [SwitchListTile(title: const Text('تنبيهات الأمان'), subtitle: const Text('إشعار عند تسجيل دخول جديد'), value:alerts, onChanged:(v)=>setState(()=>alerts=v)), SwitchListTile(title: const Text('التحقق بخطوتين'), subtitle: const Text('ميزة أمان إضافية للحساب'), value:twoFactor, onChanged:(v)=>setState(()=>twoFactor=v)), const ListTile(leading: Icon(Icons.devices), title: Text('الأجهزة المسجلة'), subtitle: Text('يمكنك مراجعة جلسات الدخول من هنا.'))])); }

class BlockedAccountsScreen extends StatelessWidget { const BlockedAccountsScreen({super.key}); @override Widget build(BuildContext context)=>Scaffold(appBar: AppBar(title: const Text('الحسابات المحظورة')), body: const Center(child: Text('لا توجد حسابات محظورة'))); }

class AccountStatusScreen extends StatefulWidget { const AccountStatusScreen({super.key}); @override State<AccountStatusScreen> createState()=>_AccountStatusScreenState(); }
class _AccountStatusScreenState extends State<AccountStatusScreen> { bool active=true; @override Widget build(BuildContext context)=>Scaffold(appBar: AppBar(title: const Text('حالة الحساب')), body: ListView(children: [SwitchListTile(title: const Text('إظهار حالة النشاط'), subtitle: const Text('السماح للأصدقاء برؤية أنك نشط'), value:active, onChanged:(v)=>setState(()=>active=v)), const ListTile(leading: Icon(Icons.check_circle, color: Colors.green), title: Text('نشاط الحساب'), subtitle: Text('الحساب يعمل بشكل طبيعي'))])); }

class HelpCenterScreen extends StatefulWidget { const HelpCenterScreen({super.key}); @override State<HelpCenterScreen> createState()=>_HelpCenterScreenState(); }
class _HelpCenterScreenState extends State<HelpCenterScreen> { final c=TextEditingController(); @override Widget build(BuildContext context)=>Scaffold(appBar: AppBar(title: const Text('مركز المساعدة')), body: Padding(padding: const EdgeInsets.all(20), child: Column(children: [const Text('اكتب مشكلتك وسيتم تسجيلها لفريق الدعم.'), const SizedBox(height:15), TextField(controller:c, maxLines:6, decoration: const InputDecoration(hintText:'اكتب الشكوى أو المشكلة', filled:true)), const SizedBox(height:15), ElevatedButton.icon(icon: const Icon(Icons.send), label: const Text('إرسال البلاغ'), onPressed: () async { if(c.text.trim().isEmpty)return; final u=FirebaseAuth.instance.currentUser; await FirebaseFirestore.instance.collection('supportTickets').add({'userId':u?.uid,'message':c.text.trim(),'createdAt':FieldValue.serverTimestamp(),'phone':'01205293436'}); if(context.mounted){c.clear(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إرسال البلاغ للدعم')));} })]))); @override void dispose(){c.dispose();super.dispose();} }

class ProfileQrScreen extends StatelessWidget {
  const ProfileQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final code = 'stvideo://profile/${user?.uid ?? 'guest'}';
    return Scaffold(
      appBar: AppBar(title: const Text('رمز الملف الشخصي')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              color: Colors.white,
              child: QrImageView(data: code, size: 210, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 15),
            const Text('شارك هذا الرمز للوصول إلى صفحتك'),
            const SizedBox(height: 8),
            SelectableText(code, textAlign: TextAlign.center),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy),
                  label: const Text('نسخ الرابط'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ رابط الملف الشخصي')));
                  },
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.share),
                  label: const Text('مشاركة'),
                  onPressed: () => Share.share('شاهد ملفي الشخصي على ST Video:\n$code', subject: 'ملفي الشخصي'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 8. البث المباشر عبر Agora// 8. البث المباشر عبر Agora (بدون Certificate - Testing mode)
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
class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});
  @override State<DiscoverScreen> createState() => _DiscoverScreenState();
}
class _DiscoverScreenState extends State<DiscoverScreen> {
  final c=TextEditingController();
  String term='';
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('بحث')), body: Column(children: [Padding(padding: const EdgeInsets.all(12), child: TextField(controller:c, autofocus:true, onChanged:(v)=>setState(()=>term=v.trim().toLowerCase()), decoration: InputDecoration(hintText:'ابحث عن حساب أو فيديو أو كلمة...', prefixIcon:const Icon(Icons.search), suffixIcon: term.isEmpty ? null : IconButton(icon:const Icon(Icons.clear), onPressed:(){ c.clear(); setState(()=>term=''); }), filled:true, border:OutlineInputBorder(borderRadius:BorderRadius.circular(28))))), Expanded(child: term.isEmpty ? const Center(child: Text('اكتب كلمة للبحث عن حسابات أو فيديوهات')) : StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(stream:FirebaseFirestore.instance.collection('videos').snapshots(), builder:(_,snap){ if(!snap.hasData)return const Center(child:CircularProgressIndicator()); final docs=snap.data!.docs.where((d){final x=d.data(); return '${x['caption']??''} ${x['username']??''} ${x['selectedSong']??''}'.toLowerCase().contains(term);}).toList(); if(docs.isEmpty)return const Center(child:Text('لا توجد نتائج')); return ListView.builder(itemCount:docs.length,itemBuilder:(_,i){final d=docs[i].data(); return ListTile(leading:const CircleAvatar(child:Icon(Icons.play_arrow)), title:Text('@${d['username']??'user'}'), subtitle:Text(d['caption']??''), onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>PublicProfileScreen(userId:d['ownerId']??'', username:d['username']??'user'))));}); }))]));
  @override void dispose(){c.dispose();super.dispose();}
}
