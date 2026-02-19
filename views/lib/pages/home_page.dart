import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import 'upload_pdf_page.dart';
import 'manage_pdf_page.dart';
import 'login_page.dart';

/// 首頁 — 登入後的主畫面
/// 底部 Tab 切換：管理 PDF / 上傳 PDF / 個人
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  String? _username;
  String? _email;
  int? _quota;

  final GlobalKey<ManagePdfPageState> _managePdfKey = GlobalKey<ManagePdfPageState>();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      ManagePdfPage(key: _managePdfKey),
      UploadPdfPage(
        onUploadSuccess: () {
          _managePdfKey.currentState?.refresh();
        },
      ),
    ];
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profileResult = await ApiService.getProfile();
    final quotaResult = await ApiService.getQuota();

    if (mounted) {
      setState(() {
        if (profileResult.success && profileResult.data != null) {
          _username = profileResult.data!.username;
          _email = profileResult.data!.email;
        }
        if (quotaResult.success && quotaResult.data != null) {
          _quota = quotaResult.data!;
        }
      });
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('登出'),
        content: const Text('確定要登出嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('登出'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await AuthService.logout();

    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }

  Widget _buildProfileTab() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircleAvatar(
              radius: 48,
              child: Icon(Icons.person, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              _username ?? '...',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _email ?? '',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: const Icon(Icons.toll, color: Colors.blue),
                title: const Text('剩餘額度'),
                trailing: Text(
                  '${_quota ?? "..."} 頁',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('登出',
                    style: TextStyle(color: Colors.red, fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ..._pages,
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          if (index == 2) _loadProfile(); // 切換到個人頁時重新載入
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.folder),
            label: '我的 PDF',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.upload),
            label: '上傳',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: '個人',
          ),
        ],
      ),
    );
  }
}
