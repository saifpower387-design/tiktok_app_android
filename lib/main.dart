import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
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
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.active) {
            final user = snapshot.data;
            if (user == null) {
              return const AuthScreen();
            } else {
              return const MainScreen();
            }
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: Colors.redAccent)),
          );
        },
      ),
    );
  }
}

// 1. شاشة المصادقة
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

    try {
      if (_isLogin) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      } else {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
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
                const Icon(Icons.tiktok, size: 80, color: Colors.redAccent),
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
    const FullCameraStudioScreen(),
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
          BottomNavigationBarItem(icon: Icon(Icons.add_box, size: 38, color: Colors.redAccent), label: 'إنشاء'),
          BottomNavigationBarItem(icon: Icon(Icons.message), label: 'الرسائل والشات'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'حسابي'),
        ],
      ),
    );
  }
}

// 3. شاشة الفيديوهات الرئيسية
class VideoFeedScreen extends StatelessWidget {
  const VideoFeedScreen({super.key});

  void _showCommentsSheet(BuildContext context, String videoId, bool commentsAllowed) {
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

  void _reportVideo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إبلاغ عن الفيديو'),
        content: const Text('هل تريد الإبلاغ عن هذا المحتوى لمخالفته الإرشادات؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم استلام بلاغك بنجاح، شكراً لمساعدتنا.')));
            },
            child: const Text('إبلاغ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _downloadVideo(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('جاري تنزيل الفيديو وحفظه في جهازك... 📥'), backgroundColor: Colors.green));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('videos').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.redAccent));
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('لا توجد فيديوهات، انشر أول فيديو من زر إنشاء! 🎬', style: TextStyle(color: Colors.white70)));
        }

        return PageView.builder(
          scrollDirection: Axis.vertical,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final videoId = docs[index].id;
            final bool commentsAllowed = data['commentsAllowed'] ?? true;

            return Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  color: Colors.grey[900],
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.play_circle_fill, size: 80, color: Colors.redAccent),
                        const SizedBox(height: 10),
                        Text(data['caption'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 18)),
                        Text('@${data['username']}', style: const TextStyle(color: Colors.grey, fontSize: 14)),
                      ],
                    ),
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
                        onPressed: () => _showCommentsSheet(context, videoId, commentsAllowed),
                      ),
                      const Text('تعليق', style: TextStyle(color: Colors.white, fontSize: 12)),
                      const SizedBox(height: 15),
                      IconButton(
                        icon: const Icon(Icons.download, size: 36, color: Colors.white),
                        onPressed: () => _downloadVideo(context),
                      ),
                      const Text('تنزيل', style: TextStyle(color: Colors.white, fontSize: 12)),
                      const SizedBox(height: 15),
                      IconButton(
                        icon: const Icon(Icons.report_problem, size: 36, color: Colors.orangeAccent),
                        onPressed: () => _reportVideo(context),
                      ),
                      const Text('إبلاغ', style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// 4. استوديو الكاميرا ونشر الفيديو
class FullCameraStudioScreen extends StatelessWidget {
  const FullCameraStudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استوديو النشر')),
      body: Center(
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.all(16)),
          icon: const Icon(Icons.video_library, color: Colors.white),
          label: const Text('اختر فيديو وانشره الآن 🚀', style: TextStyle(color: Colors.white, fontSize: 16)),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const UploadPostScreen())),
        ),
      ),
    );
  }
}

class UploadPostScreen extends StatefulWidget {
  const UploadPostScreen({super.key});

  @override
  State<UploadPostScreen> createState() => _UploadPostScreenState();
}

class _UploadPostScreenState extends State<UploadPostScreen> {
  final _captionController = TextEditingController();
  File? _selectedVideoFile;
  bool _isUploading = false;
  bool _commentsAllowed = true;

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _selectedVideoFile = File(pickedFile.path));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم اختيار الفيديو بنجاح! 🎬'), backgroundColor: Colors.green));
    }
  }

  void _upload() async {
    if (_selectedVideoFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر فيديو أولاً!'), backgroundColor: Colors.red));
      return;
    }
    setState(() => _isUploading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      final ref = FirebaseStorage.instance.ref().child('videos').child('${DateTime.now().millisecondsSinceEpoch}.mp4');
      await ref.putFile(_selectedVideoFile!);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('videos').add({
        'videoUrl': url,
        'caption': _captionController.text,
        'uid': user?.uid,
        'username': user?.email?.split('@')[0] ?? 'user',
        'commentsAllowed': _commentsAllowed,
        'createdAt': Timestamp.now(),
      });

      setState(() => _isUploading = false);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم النشر بنجاح لكل المستخدمين! 🚀'), backgroundColor: Colors.green));
    } catch (e) {
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('رفع الفيديو')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _selectedVideoFile == null ? Colors.grey[850] : Colors.green),
              icon: const Icon(Icons.video_library),
              label: Text(_selectedVideoFile == null ? 'اختر فيديو من الجهاز' : 'تم اختيار الفيديو'),
              onPressed: _pickVideo,
            ),
            const SizedBox(height: 20),
            TextField(controller: _captionController, maxLines: 3, decoration: const InputDecoration(hintText: 'اكتب وصف الفيديو..', filled: true)),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text('السماح بالتعليقات على الفيديو'),
              subtitle: Text(_commentsAllowed ? 'التعليقات مفتوحة للجميع' : 'التعليقات مغلقة'),
              value: _commentsAllowed,
              activeColor: Colors.redAccent,
              onChanged: (val) => setState(() => _commentsAllowed = val),
            ),
            const SizedBox(height: 20),
            _isUploading ? const Center(child: CircularProgressIndicator(color: Colors.redAccent)) : ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.all(14)),
              onPressed: _upload,
              child: const Text('نشر الفيديو الآن 🚀', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

// 5. صفحة الرسائل والإشعارات والشات
class InboxScreen extends StatelessWidget {
  const InboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الرسائل والإشعارات'),
          bottom: const TabBar(
            indicatorColor: Colors.redAccent,
            tabs: [
              Tab(text: 'الإشعارات 🔔'),
              Tab(text: 'الشات والمحادثات 💬'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView.builder(
              itemCount: 5,
              itemBuilder: (context, index) => ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.notifications, color: Colors.white)),
                title: Text('إشعار تفاعل رقم ${index + 1}'),
                subtitle: const Text('قام أحد المستخدمين بالإعجاب بفيديوهاتك ومتابعتك.'),
                trailing: const Text('منذ 10د', style: TextStyle(color: Colors.grey, fontSize: 11)),
              ),
            ),
            ListView.builder(
              itemCount: 4,
              itemBuilder: (context, index) => ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.purple, child: Icon(Icons.person, color: Colors.white)),
                title: Text('صديق تيك توك ${index + 1}'),
                subtitle: const Text('أرسل لك رسالة جديدة...'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => ChatRoomScreen(friendName: 'صديق تيك توك ${index + 1}')),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatRoomScreen extends StatefulWidget {
  final String friendName;
  const ChatRoomScreen({super.key, required this.friendName});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> {
  final TextEditingController _msgController = TextEditingController();
  final List<String> _messages = ['أهلاً بك يا بطل!', 'كيف حالك مع مشروع التيك توك؟'];

  void _sendMessage() {
    if (_msgController.text.trim().isEmpty) return;
    setState(() {
      _messages.add(_msgController.text.trim());
      _msgController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.friendName)),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_messages[index], style: const TextStyle(color: Colors.white)),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالة...',
                      filled: true,
                      fillColor: Colors.grey,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.redAccent),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 6. صفحة الملف الشخصي والبث المباشر
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const int followers = 160;
    return Scaffold(
      appBar: AppBar(
        title: const Text('حسابي'),
        actions: [IconButton(icon: const Icon(Icons.logout, color: Colors.red), onPressed: () => FirebaseAuth.instance.signOut())],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
            const SizedBox(height: 10),
            Text('@${FirebaseAuth.instance.currentUser?.email?.split('@')[0] ?? 'user'}', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
              onPressed: () {
                if (followers < 150) {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('عذراً'),
                      content: const Text('يجب أن تمتلك 150 متابع لفتح البث المباشر.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('حسناً'))],
                    ),
                  );
                } else {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const LiveStreamScreen()));
                }
              },
              child: const Text('بدء بث مباشر 🔴 (شرط 150 متابع)', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

class LiveStreamScreen extends StatelessWidget {
  const LiveStreamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> gifts = [
      {'name': 'وردة 🌹', 'price': 10},
      {'name': 'سيارة 🚗', 'price': 100},
      {'name': 'أسد 🦁', 'price': 500},
    ];

    return Scaffold(
      body: Stack(
        children: [
          Container(
            color: Colors.black,
            child: const Center(child: Text('🔴 أنت الآن في بث مباشر حقيقي مع المتابعين', style: TextStyle(color: Colors.white, fontSize: 18))),
          ),
          Positioned(
            top: 40,
            left: 16,
            child: IconButton(icon: const Icon(Icons.exit_to_app, color: Colors.white, size: 30), onPressed: () => Navigator.pop(context)),
          ),
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: SizedBox(
              height: 70,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: gifts.length,
                itemBuilder: (context, index) {
                  final gift = gifts[index];
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم إرسال ${gift['name']} بنجاح! 🎉')));
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(gift['name']),
                          Text('${gift['price']} عملة', style: const TextStyle(fontSize: 10, color: Colors.amber)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 7. صفحة اكتشف الترندات
class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اكتشف الترندات')),
      body: GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10),
        itemCount: 4,
        itemBuilder: (context, index) => Container(color: Colors.grey[850], child: Center(child: Text('#هاشتاج_${index + 1}', style: const TextStyle(color: Colors.white)))),
      ),
    );
  }
}
