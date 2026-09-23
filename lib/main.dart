import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera/camera.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';

// نموذج بيانات الفيديو مع دعم الحفظ المستمر
class VideoItem {
  final String videoPath;
  final String caption;
  final String username;
  final bool commentsAllowed;
  final String selectedSong;

  VideoItem({
    required this.videoPath,
    required this.caption,
    required this.username,
    required this.commentsAllowed,
    required this.selectedSong,
  });

  Map<String, dynamic> toJson() => {
        'videoPath': videoPath,
        'caption': caption,
        'username': username,
        'commentsAllowed': commentsAllowed,
        'selectedSong': selectedSong,
      };

  factory VideoItem.fromJson(Map<String, dynamic> json) => VideoItem(
        videoPath: json['videoPath'] ?? '',
        caption: json['caption'] ?? '',
        username: json['username'] ?? 'saif_creator',
        commentsAllowed: json['commentsAllowed'] ?? true,
        selectedSong: json['selectedSong'] ?? 'أغنية الحماس والترند 🎵',
      );
}

// مدير تخزين البيانات محلياً لضمان عدم ضياع أي شيء
class LocalStorageManager {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> saveData({
    required bool isLoggedIn,
    required String email,
    required String name,
    required String phone,
    required int balance,
    required List<VideoItem> videos,
  }) async {
    await _prefs.setBool('isLoggedIn', isLoggedIn);
    await _prefs.setString('userEmail', email);
    await _prefs.setString('userName', name);
    await _prefs.setString('userPhone', phone);
    await _prefs.setInt('userBalance', balance);
    
    List<String> encodedVideos = videos.map((v) => jsonEncode(v.toJson())).toList();
    await _prefs.setStringList('publishedVideos', encodedVideos);
  }

  static bool getIsLoggedIn() => _prefs.getBool('isLoggedIn') ?? false;
  static String getEmail() => _prefs.getString('userEmail') ?? 'saif_user@tiktok.com';
  static String getName() => _prefs.getString('userName') ?? 'سيف المبرمج';
  static String getPhone() => _prefs.getString('userPhone') ?? '+20 1000000000';
  static int getBalance() => _prefs.getInt('userBalance') ?? 1250;

  static List<VideoItem> getVideos() {
    List<String>? encodedVideos = _prefs.getStringList('publishedVideos');
    if (encodedVideos == null) return [];
    return encodedVideos.map((str) => VideoItem.fromJson(jsonDecode(str))).toList();
  }
}

class AppData {
  static List<VideoItem> publishedVideos = [];
  static bool isLoggedIn = false;
  static String userEmail = '';
  static String userName = '';
  static String userPhone = '';
  static int userBalance = 0;
  static List<CameraDescription> cameras = [];

  static Future<void> loadFromStorage() async {
    await LocalStorageManager.init();
    isLoggedIn = LocalStorageManager.getIsLoggedIn();
    userEmail = LocalStorageManager.getEmail();
    userName = LocalStorageManager.getName();
    userPhone = LocalStorageManager.getPhone();
    userBalance = LocalStorageManager.getBalance();
    publishedVideos = LocalStorageManager.getVideos();
  }

  static Future<void> syncToStorage() async {
    await LocalStorageManager.saveData(
      isLoggedIn: isLoggedIn,
      email: userEmail,
      name: userName,
      phone: userPhone,
      balance: userBalance,
      videos: publishedVideos,
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    AppData.cameras = await availableCameras();
  } catch (e) {
    debugPrint("خطأ في تشغيل الكاميرات: $e");
  }
  await AppData.loadFromStorage();
  runApp(const TikTokCloneApp());
}

class TikTokCloneApp extends StatelessWidget {
  const TikTokCloneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'St TikTok Pro',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        primaryColor: Colors.redAccent,
        colorScheme: ColorScheme.dark(
          primary: Colors.redAccent,
          secondary: Colors.amberAccent,
          surface: const Color(0xFF1E1E1E),
        ),
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

  void _loginWithSocial(String providerName, Color themeColor) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_new, size: 50, color: themeColor),
            const SizedBox(height: 15),
            Text('جاري فتح تطبيق $providerName...', style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 15),
            const CircularProgressIndicator(color: Colors.redAccent),
            const SizedBox(height: 10),
            const Text('يرجى تأكيد الصلاحية للمتابعة', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () async {
      if (mounted) {
        Navigator.pop(context);
        AppData.isLoggedIn = true;
        AppData.userEmail = 'user_$providerName@social.com';
        await AppData.syncToStorage();
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تسجيل الدخول عبر $providerName بنجاح! 🚀'), backgroundColor: Colors.green),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    });
  }

  void _submitAuthForm() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('من فضلك أدخل البريد وكلمة المرور')),
      );
      return;
    }

    setState(() => _isLoading = true);

    AppData.isLoggedIn = true;
    AppData.userEmail = email;
    await AppData.syncToStorage();

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    });
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
                // تصميم شعار S مع T احترافي
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Colors.redAccent, Colors.purpleAccent]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text(
                      'Sₜ',
                      style: TextStyle(fontSize: 45, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(_isLogin ? 'تسجيل الدخول إلى St Pro' : 'إنشاء حساب جديد 🚀', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 30),
                TextField(controller: _emailController, decoration: InputDecoration(hintText: 'البريد الإلكتروني', filled: true, fillColor: Colors.grey[900], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none))),
                const SizedBox(height: 15),
                TextField(controller: _passwordController, obscureText: true, decoration: InputDecoration(hintText: 'كلمة المرور', filled: true, fillColor: Colors.grey[900], border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none))),
                const SizedBox(height: 25),
                _isLoading
                    ? const CircularProgressIndicator(color: Colors.redAccent)
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: _submitAuthForm,
                        child: Text(_isLogin ? 'دخول' : 'تسجيل', style: const TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(_isLogin ? 'ليس لديك حساب؟ أنشئ حساباً' : 'لديك حساب؟ سجل دخولك', style: const TextStyle(color: Colors.amberAccent)),
                ),
                const Divider(height: 30, color: Colors.grey),
                const Text('أو المتابعة بربط التطبيقات الخارجية', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 15),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.g_mobiledata, size: 40, color: Colors.white),
                      style: IconButton.styleFrom(backgroundColor: Colors.grey[900]),
                      onPressed: () => _loginWithSocial('Google', Colors.redAccent),
                    ),
                    const SizedBox(width: 15),
                    IconButton(
                      icon: const Icon(Icons.facebook, size: 30, color: Colors.blueAccent),
                      style: IconButton.styleFrom(backgroundColor: Colors.grey[900]),
                      onPressed: () => _loginWithSocial('Facebook', Colors.blueAccent),
                    ),
                    const SizedBox(width: 15),
                    IconButton(
                      icon: const Icon(Icons.camera_alt, size: 28, color: Colors.pinkAccent),
                      style: IconButton.styleFrom(backgroundColor: Colors.grey[900]),
                      onPressed: () => _loginWithSocial('Instagram', Colors.pinkAccent),
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

// 2. الشاشة الرئيسية للتنقل
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

// 3. شاشة الـ Feed الرئيسي مع خانة البحث
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
            child: Center(child: Text('التعليقات مغلقة لهذا الفيديو بواسطة صاحب المنشور 🔒', style: TextStyle(color: Colors.white70))),
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
        );
      },
    );
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
                        video.videoPath.isNotEmpty && File(video.videoPath).existsSync()
                            ? Image.file(File(video.videoPath), fit: BoxFit.cover)
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
            child: TextField(
              controller: _searchController,
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
    );
  }
}

// 4. استوديو الكاميرا مع خيارات متقدمة ومعرض وأوضاع التصوير
class CameraStudioScreen extends StatefulWidget {
  const CameraStudioScreen({super.key});

  @override
  State<CameraStudioScreen> createState() => _CameraStudioScreenState();
}

class _CameraStudioScreenState extends State<CameraStudioScreen> {
  CameraController? _controller;
  bool _isCameraInitialized = false;
  String _selectedMode = 'فيديو';
  String _selectedFilter = 'بدون فلتر';
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (AppData.cameras.isNotEmpty) {
      _controller = CameraController(AppData.cameras[0], ResolutionPreset.high);
      try {
        await _controller!.initialize();
        if (mounted) setState(() => _isCameraInitialized = true);
      } catch (e) {
        debugPrint("خطأ فتح الكاميرا: $e");
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
    if (pickedFile != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => UploadPostScreen(mediaPath: pickedFile.path)),
      );
    }
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
            label: const Text('اختر من المعرض'),
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
          Positioned(
            top: 50,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.face, color: Colors.white, size: 32),
              onPressed: () {
                setState(() {
                  _selectedFilter = _selectedFilter == 'فلتر جمالي دافئ' ? 'فلتر نيون أزرق' : 'فلتر جمالي دافئ';
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تفعيل: $_selectedFilter ✨')));
              },
            ),
          ),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Column(
              children: [
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
                            color: isSelected ? Colors.amberAccent : Colors.white,
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
                    IconButton(
                      icon: const Icon(Icons.photo_library, color: Colors.white, size: 36),
                      onPressed: _pickFromGallery,
                    ),
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
                    const SizedBox(width: 36),
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

// 5. شاشة النشر مع الأغاني ومستويات الصوت
class UploadPostScreen extends StatefulWidget {
  final String mediaPath;
  const UploadPostScreen({super.key, required this.mediaPath});

  @override
  State<UploadPostScreen> createState() => _UploadPostScreenState();
}

class _UploadPostScreenState extends State<UploadPostScreen> {
  final TextEditingController _captionController = TextEditingController();
  bool _commentsAllowed = true;
  String _selectedSong = 'أغنية الحماس والترند 🎵';
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
                    height: 140,
                    child: ListView.builder(
                      itemCount: availableSongs.length,
                      itemBuilder: (context, index) {
                        final song = availableSongs[index];
                        return ListTile(
                          title: Text(song, style: const TextStyle(color: Colors.white)),
                          trailing: _selectedSong == song ? const Icon(Icons.check, color: Colors.amberAccent) : null,
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
                  Row(
                    children: [
                      const Text('الأصلي', style: TextStyle(color: Colors.white, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _originalSoundVolume,
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
                      const Text('المضاف', style: TextStyle(color: Colors.white, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: _addedSongVolume,
                          activeColor: Colors.amberAccent,
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

  void _publishVideo() async {
    final newVideo = VideoItem(
      videoPath: widget.mediaPath,
      caption: _captionController.text.trim().isEmpty ? 'فيديو جديد على St Pro 🔥' : _captionController.text.trim(),
      username: 'saif_creator',
      commentsAllowed: _commentsAllowed,
      selectedSong: _selectedSong,
    );

    AppData.publishedVideos.insert(0, newVideo);
    await AppData.syncToStorage(); // حفظ البيانات فوراً

    if (mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نشر الفيديو بنجاح وحفظه في حسابك! 🚀'), backgroundColor: Colors.green));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('معاينة ونشر المحتوى'),
        actions: [
          IconButton(
            icon: const Icon(Icons.music_note, color: Colors.amberAccent),
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
              decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.music_note, color: Colors.amberAccent),
                  const SizedBox(width: 10),
                  Expanded(child: Text('الأغنية: $_selectedSong', style: const TextStyle(color: Colors.white))),
                  TextButton(onPressed: _openSongsPicker, child: const Text('تغيير', style: TextStyle(color: Colors.amberAccent))),
                ],
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _captionController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'اكتب وصف الفيديو...',
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[850]),
                  icon: const Icon(Icons.tag, color: Colors.amberAccent),
                  label: const Text('هاشتاج #'),
                  onPressed: () => _insertText(' #ترند_St '),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.all(14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: _publishVideo,
              child: const Text('نشر الآن 🚀', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

// 6. صفحة الرسائل
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
          title: Text('صديق المنصة ${index + 1}'),
          subtitle: const Text('أرسل لك تفاعلاً جديداً...'),
        ),
      ),
    );
  }
}

// 7. صفحة الملف الشخصي الاحترافية
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
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعديل الملف الشخصي'))),
                child: const Text('تعديل الملف الشخصي', style: TextStyle(color: Colors.white)),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم نسخ رابط الملف الشخصي! 🔗'))),
                child: const Text('مشاركة الملف الشخصي', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.grey),
          const Text('الفيديوهات المنشورة 🎬', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 10),
          Expanded(
            child: userVideos.isEmpty
                .?(const Center(child: Text('لم تقم بنشر أي فيديوهات بعد', style: TextStyle(color: Colors.grey))))
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
                        decoration: BoxDecoration(color: Colors.grey[850], borderRadius: BorderRadius.circular(8)),
                        child: const Center(child: Icon(Icons.play_arrow, color: Colors.white, size: 30)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// 8. صفحة الإعدادات مع معلومات الحساب، الرصيد، وتسجيل الخروج
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
            leading: const Icon(Icons.account_balance_wallet, color: Colors.amberAccent),
            title: const Text('الرصيد والأرباح'),
            subtitle: Text('رصيدك الحالي: ${AppData.userBalance} عملة 💰'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('رصيد الحساب'),
                  content: Text('لديك الآن ${AppData.userBalance} عملة قابلة للسحب والأرباح.'),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.all(12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text('تسجيل الخروج من الحساب', style: TextStyle(color: Colors.white, fontSize: 16)),
              onPressed: () async {
                AppData.isLoggedIn = false;
                await AppData.syncToStorage();
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const AuthScreen()),
                    (route) => false,
                  );
                }
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
      body: const Center(child: Text('🔴 أنت الآن في بث مباشر مع المتابعين', style: TextStyle(color: Colors.white, fontSize: 18))),
    );
  }
}

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
          decoration: BoxDecoration(color: Colors.grey[850], borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text('#هاشتاج_St_${index + 1} 🔥', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ),
      ),
    );
  }
}
