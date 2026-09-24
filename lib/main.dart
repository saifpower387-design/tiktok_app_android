import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';

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
      final account = await GoogleSignIn().signIn();
      if (account == null) return;
      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = result.user!;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName ?? 'مستخدم جديد',
        'photoUrl': user.photoURL,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      AppData.isLoggedIn = true;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل Google: ${e.message ?? e.code}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تسجيل Google: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitAuthForm() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    if (email.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل بريدًا صحيحًا وكلمة مرور من 6 أحرف على الأقل')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = _isLogin
          ? await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password)
          : await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      final user = result.user!;
      AppData.isLoggedIn = true;
      AppData.userEmail = user.email ?? email;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName ?? email.split('@').first,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تسجيل الدخول: ${e.message ?? e.code}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حدث خطأ: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.music_video, size: 80, color: Colors.redAccent),
                const SizedBox(height: 20),
                Text(_isLogin ? 'تسجيل الدخول لتيك توك' : 'إنشاء حساب جديد 🚀', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                TextField(controller: _emailController, decoration: const InputDecoration(hintText: 'البريد الإلكتروني', filled: true)),
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
                const Divider(height: 30, color: Colors.grey),
                const Text('أو المتابعة بربط التطبيقات الخارجية', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.g_mobiledata, size: 45, color: Colors.white),
                      style: IconButton.styleFrom(backgroundColor: Colors.grey[900]),
                      onPressed: () => _loginWithSocial('Google (Gmail)', Colors.redAccent),
                      tooltip: 'تسجيل بـ Gmail',
                    ),
                    const SizedBox(width: 15),
                    IconButton(
                      icon: const Icon(Icons.facebook, size: 35, color: Colors.blueAccent),
                      style: IconButton.styleFrom(backgroundColor: Colors.grey[900]),
                      onPressed: () => _loginWithSocial('Facebook', Colors.blueAccent),
                      tooltip: 'تسجيل بـ Facebook',
                    ),
                    const SizedBox(width: 15),
                    IconButton(
                      icon: const Icon(Icons.camera_alt, size: 32, color: Colors.pinkAccent),
                      style: IconButton.styleFrom(backgroundColor: Colors.grey[900]),
                      onPressed: () => _loginWithSocial('Instagram', Colors.pinkAccent),
                      tooltip: 'تسجيل بـ Instagram',
                    ),
                  ],
                ),
              ],
            ),
          ),
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
      ..initialize().then((_) { if (mounted) setState(() {}); });
  }
  @override
  void dispose() { _controller.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) return const Center(child: CircularProgressIndicator());
    return GestureDetector(
      onTap: () { setState(() { _controller.value.isPlaying ? _controller.pause() : _controller.play(); }); },
      child: FittedBox(fit: BoxFit.cover, child: SizedBox(width: _controller.value.size.width, height: _controller.value.size.height, child: VideoPlayer(_controller))),
    );
  }
}

// 3. شاشة الفيديوهات الرئيسية مع خانة بحث علوية
class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> {
  final TextEditingController _searchController = TextEditingController();

  void _showCommentsSheet(BuildContext context, bool commentsAllowed) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (context) {
        if (!commentsAllowed) {
          return const SizedBox(
            height: 200,
            child: Center(
              child: Text('التعليقات مغلقة لهذا الفيديو بواسطة صاحب المنشور 🔒', style: TextStyle(color: Colors.white70)),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('التعليقات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
              const Expanded(child: Center(child: Text('لا توجد تعليقات بعد.. كن أول من يعلق!', style: TextStyle(color: Colors.grey)))),
              TextField(
                decoration: InputDecoration(
                  hintText: 'اكتب تعليقاً...',
                  filled: true,
                  fillColor: Colors.black,
                  suffixIcon: IconButton(icon: const Icon(Icons.send, color: Colors.redAccent), onPressed: () {}),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final videos = AppData.publishedVideos;

    return Scaffold(
      body: Stack(
        children: [
          videos.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد فيديوهات منشورة حالياً..\nاضغط على علامة (+) لتصوير ونشر أول فيديو! 🎥',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : PageView.builder(
                  scrollDirection: Axis.vertical,
                  itemCount: videos.length,
                  itemBuilder: (context, index) {
                    final video = videos[index];
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        video.downloadUrl.isNotEmpty && video.mediaType == 'image'
                            ? Image.network(video.downloadUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black))
                            : video.downloadUrl.isNotEmpty && video.mediaType == 'video'
                                ? RemoteVideo(url: video.downloadUrl)
                                : Container(
                                    color: Colors.grey[900],
                                    child: const Center(child: Icon(Icons.play_circle_fill, size: 80, color: Colors.redAccent)),
                                  ),
                        Positioned(
                          left: 15,
                          bottom: 80,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('@${video.username}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              const SizedBox(height: 5),
                              Text(video.caption, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                              const SizedBox(height: 5),
                              Row(
                                children: [
                                  const Icon(Icons.music_note, color: Colors.white, size: 14),
                                  const SizedBox(width: 5),
                                  Text(video.selectedSong, style: const TextStyle(color: Colors.white, fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 15,
                          bottom: 80,
                          child: Column(
                            children: [
                              const Icon(Icons.favorite, size: 38, color: Colors.red),
                              const Text('1.2K', style: TextStyle(color: Colors.white)),
                              const SizedBox(height: 15),
                              IconButton(
                                icon: const Icon(Icons.comment, size: 36, color: Colors.white),
                                onPressed: () => _showCommentsSheet(context, video.commentsAllowed),
                              ),
                              const Text('تعليق', style: TextStyle(color: Colors.white, fontSize: 12)),
                              const SizedBox(height: 15),
                              IconButton(
                                icon: const Icon(Icons.share, size: 36, color: Colors.white),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ رابط الفيديو!')));
                                },
                              ),
                              const Text('مشاركة', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
          Positioned(
            top: 40,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'ابحث عن مستخدمين، هاشتاجات، أو فيديوهات...',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      filled: true,
                      fillColor: Colors.black54,
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
              ],
            ),
          ),
          // زر التقاط الصورة / الفيديو / البث السفلي مع خيار المعرض والوضع
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Column(
              children: [
                // التبديل بين الأضاع (صورة، فيديو، بث مباشر)
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
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const LiveStreamScreen()));
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
  bool _commentsAllowed = true;
  String _selectedSong = 'أغنية الحماس والترند 🎵'; // أغنية افتراضية تليق بالصورة/الفيديو تلقائياً
  double _originalSoundVolume = 0.8;
  double _addedSongVolume = 0.5;

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
    if (user == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('سجل الدخول أولًا'))); return; }
    setState(() {});
    try {
      final id = FirebaseFirestore.instance.collection('videos').doc().id;
      final isImage = widget.mediaPath.toLowerCase().endsWith('.jpg') || widget.mediaPath.toLowerCase().endsWith('.jpeg') || widget.mediaPath.toLowerCase().endsWith('.png');
      final ext = isImage ? 'jpg' : 'mp4';
      final ref = FirebaseStorage.instance.ref('videos/${user.uid}/$id.$ext');
      await ref.putFile(File(widget.mediaPath), SettableMetadata(contentType: isImage ? 'image/jpeg' : 'video/mp4'));
      final url = await ref.getDownloadURL();
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
      });
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم رفع ونشر المحتوى على Firebase بنجاح'), backgroundColor: Colors.green));
    } on FirebaseException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل رفع المحتوى: ${e.message ?? e.code}')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل النشر: $e')));
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
              onPressed: _publishVideo,
              child: const Text('نشر الآن 🚀', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// 5. صفحة الرسائل
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الرسائل والإشعارات')),
      body: ListView.builder(
        itemCount: 3,
        itemBuilder: (context, index) => ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.person, color: Colors.white)),
          title: Text('صديق تيك توك ${index + 1}'),
          subtitle: const Text('أرسل لك إعجاباً ومراسلة جديدة...'),
        ),
      ),
    );
  }
}

// 6. صفحة الملف الشخصي بالترتيب المطلوب مع أزرار متجاورة وقائمة إعدادات جانبية
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userVideos = AppData.publishedVideos;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppData.userName),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const SettingsScreen()));
            },
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 15),
          const CircleAvatar(radius: 45, backgroundColor: Colors.redAccent, child: Icon(Icons.person, size: 55, color: Colors.white)),
          const SizedBox(height: 10),
          Text(AppData.userName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          const Text('@saif_creator', style: TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey)),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فتح نافذة تعديل الملف الشخصي')));
                },
                child: const Text('تعديل الملف الشخصي', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey)),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ رابط ملفك الشخصي بنجاح! 🔗')));
                },
                child: const Text('مشاركة الملف الشخصي', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.grey),
          const Text('الفيديوهات المنشورة الخاصة بك 🎬', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 10),
          Expanded(
            child: userVideos.isEmpty
                ? const Center(child: Text('لم تقم بنشر أي فيديوهات بعد', style: TextStyle(color: Colors.grey)))
                : GridView.builder(
                    padding: const EdgeInsets.all(5),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 5,
                      mainAxisSpacing: 5,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: userVideos.length,
                    itemBuilder: (context, index) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[850],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Icon(Icons.play_arrow, color: Colors.white, size: 30),
                        ),
                      );
                    },
                  ),
          ),
        ],
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
            subtitle: Text('الاسم: ${AppData.userName}\nالرقم: ${AppData.userPhone}\nالبريد: ${AppData.userEmail}'),
            isThreeLine: true,
          ),
          const Divider(color: Colors.grey),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet, color: Colors.amber),
            title: const Text('الرصيد والأرباح'),
            subtitle: Text('رصيدك الحالي: ${AppData.userBalance} عملة 💰'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('رصيد الحساب'),
                  content: Text('لديك الآن ${AppData.userBalance} عملة من أرباح البثوث والفيديوهات.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
                ),
              );
            },
          ),
          const Divider(color: Colors.grey),
          const SizedBox(height: 40),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.all(12)),
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text('تسجيل الخروج من الحساب', style: TextStyle(color: Colors.white, fontSize: 16)),
              onPressed: () {
                AppData.isLoggedIn = false;
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

class LiveStreamScreen extends StatelessWidget {
  const LiveStreamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('البث المباشر')),
      body: const Center(
        child: Text('🔴 أنت الآن في بث مباشر مع المتابعين', style: TextStyle(color: Colors.white, fontSize: 18)),
      ),
    );
  }
}

// 8. صفحة اكتشف الترندات
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
            color: Colors.grey[850],
            borderRadius: BorderRadius.circular(12),
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
