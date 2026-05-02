import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../state/app_state.dart';
import '../widgets/app_update_banner.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _loginIdController;
  late final TextEditingController _passwordController;
  bool _isSubmitting = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loginIdController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _loginIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final appState = context.read<AppState>();
    setState(() {
      _isSubmitting = true;
      _errorMessage = '';
    });

    try {
      await appState.login(
        _loginIdController.text,
        _passwordController.text,
        rememberMe: appState.rememberMe,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = _describeLoginError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final setupBlocked =
        appState.setupRequired && !appState.bootstrapConfigured;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'EasyPOS Mobile',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            color: Color(0xFF0F766E),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '운영 콘솔 로그인',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                        ),
                        const SizedBox(height: 20),
                        if (appState.hasRecommendedUpdate) ...[
                          const AppUpdateBanner(),
                          const SizedBox(height: 16),
                        ],
                        if (appState.offlineMode) ...[
                          _buildInfoBanner(
                            backgroundColor: const Color(0xFFECFEFF),
                            borderColor: const Color(0xFFA5F3FC),
                            textColor: const Color(0xFF155E75),
                            message: '저장된 세션과 캐시로 오프라인 모드가 유지되고 있습니다.',
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (setupBlocked) ...[
                          _buildInfoBanner(
                            backgroundColor: const Color(0xFFFFF7ED),
                            borderColor: const Color(0xFFFED7AA),
                            textColor: const Color(0xFF9A3412),
                            message:
                                '초기 관리자 계정이 아직 준비되지 않았습니다. `EASYPOS_ADMIN_BOOTSTRAP_ID`, `EASYPOS_ADMIN_BOOTSTRAP_PASSWORD`를 먼저 설정해야 합니다.',
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_errorMessage.isNotEmpty) ...[
                          _buildInfoBanner(
                            backgroundColor: const Color(0xFFFFF1F2),
                            borderColor: const Color(0xFFFECDD3),
                            textColor: const Color(0xFF9F1239),
                            message: _errorMessage,
                          ),
                          const SizedBox(height: 16),
                        ],
                        TextField(
                          controller: _loginIdController,
                          decoration: const InputDecoration(
                            labelText: '아이디',
                            border: OutlineInputBorder(),
                          ),
                          autofillHints: const [AutofillHints.username],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: '비밀번호',
                            border: OutlineInputBorder(),
                          ),
                          obscureText: true,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _isSubmitting ? null : _submit(),
                        ),
                        const SizedBox(height: 8),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          value: appState.rememberMe,
                          onChanged: _isSubmitting || setupBlocked
                              ? null
                              : (value) {
                                  appState.setRememberMe(value ?? false);
                                },
                          title: const Text(
                            '로그인 상태 유지',
                            style: TextStyle(fontSize: 14),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed:
                              _isSubmitting || setupBlocked ? null : _submit,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(_isSubmitting ? '로그인 중...' : '로그인'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _describeLoginError(Object error) {
    if (error is ApiException) {
      switch (error.statusCode) {
        case 401:
          return '아이디 또는 비밀번호가 올바르지 않습니다.';
        case 403:
          return error.message.isNotEmpty
              ? error.message
              : '로그인 요청이 서버 설정과 일치하지 않습니다. API 주소를 확인하세요.';
        case 423:
          return error.message.isNotEmpty
              ? error.message
              : '계정이 잠겨 있습니다. 잠시 후 다시 시도하세요.';
        case 429:
          return error.message.isNotEmpty
              ? error.message
              : '로그인 시도가 너무 많습니다. 잠시 후 다시 시도하세요.';
        case 504:
          return '로그인 요청 시간이 초과되었습니다. 서버 연결을 확인하세요.';
        default:
          return error.message.isNotEmpty ? error.message : '로그인 처리 중 오류가 발생했습니다.';
      }
    }
    return '로그인 서버에 연결하지 못했습니다. API 요청 주소를 확인하세요.';
  }

  Widget _buildInfoBanner({
    required Color backgroundColor,
    required Color borderColor,
    required Color textColor,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }
}
