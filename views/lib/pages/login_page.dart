import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import 'home_page.dart';

/// ============================================================
///  ⚠️ Google OAuth Client ID 設定
///  這是「Web 應用程式」類型的 Client ID，用途：
///    - Web 平台：作為 clientId 傳入 GoogleSignIn
///    - Android：作為 serverClientId，讓 SDK 回傳 idToken 給後端驗證
///  Android 的 OAuth Client ID 由 SDK 自動透過 SHA-1 + packageName 解析。
/// ============================================================
const String _googleWebClientId =
    '818391536195-vop2sgq7ckpusald1mtr3rjvbuiajfj2.apps.googleusercontent.com';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _isGoogleLoading = false;
  late final GoogleSignIn _googleSignIn;

  @override
  void initState() {
    super.initState();
    _googleSignIn = GoogleSignIn(
      // Web: 傳入 Web 類型 clientId
      // Android/iOS: clientId 留 null，SDK 自動匹配
      clientId: kIsWeb ? _googleWebClientId : null,
      // Android: 需要 serverClientId (Web 類型) 才能拿到 idToken
      serverClientId: kIsWeb ? null : _googleWebClientId,
      scopes: ['email', 'profile'],
    );

    // 監聽登入狀態變化（Web 自動登入會觸發）
    _googleSignIn.onCurrentUserChanged.listen(_handleGoogleUser);
    // 嘗試靜默登入（已登入過的使用者可自動恢復 session）
    _googleSignIn.signInSilently();
  }

  /// 處理 Google 登入結果（Web 由 stream 觸發，Mobile 由 signIn 回傳）
  Future<void> _handleGoogleUser(GoogleSignInAccount? account) async {
    if (account == null) return;
    setState(() => _isGoogleLoading = true);

    try {
      final auth = await account.authentication;
      final idToken = auth.idToken;

      if (idToken == null) {
        _showError('無法取得 Google ID Token');
        setState(() => _isGoogleLoading = false);
        return;
      }

      final result = await ApiService.googleLogin(
        idToken: idToken,
        email: account.email,
        displayName: account.displayName,
      );

      setState(() => _isGoogleLoading = false);
      if (!mounted) return;

      if (result.success) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      } else {
        _showError(result.message ?? 'Google 登入失敗');
      }
    } catch (e) {
      setState(() => _isGoogleLoading = false);
      _showError('Google 登入錯誤：$e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  /// Mobile 平台：手動觸發 signIn
  Future<void> _triggerGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        // 使用者取消
        setState(() => _isGoogleLoading = false);
        return;
      }
      await _handleGoogleUser(account);
    } catch (e) {
      setState(() => _isGoogleLoading = false);
      _showError('Google 登入錯誤：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.picture_as_pdf, size: 100, color: Colors.red),
              const SizedBox(height: 20),
              const Text(
                'PDF Editor',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '使用 Google 帳號快速登入',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 48),

              // ---------- Google 登入按鈕（全平台統一） ----------
              ElevatedButton.icon(
                onPressed: _isGoogleLoading ? null : _triggerGoogleSignIn,
                icon: _isGoogleLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Image.network(
                        'https://developers.google.com/identity/images/g-logo.png',
                        height: 22,
                        width: 22,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.g_mobiledata, size: 24),
                      ),
                label: const Text('使用 Google 帳號登入',
                    style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),

              // 登入中顯示進度指示
              if (_isGoogleLoading) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
