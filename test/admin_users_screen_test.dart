import 'package:cafe_bridge_flutter/screens/admin_users.dart';
import 'package:cafe_bridge_flutter/services/api.dart';
import 'package:cafe_bridge_flutter/services/cache_store.dart';
import 'package:cafe_bridge_flutter/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _AdminUsersAppState extends AppState {
  bool isAdmin = true;
  bool failUserFetch = false;
  bool emptyResponses = false;
  ApiException? writeError;
  final reads = <({String endpoint, Map<String, Object?>? params})>[];
  final writes = <({
    String endpoint,
    String method,
    Map<String, dynamic>? body,
  })>[];

  final users = <Map<String, dynamic>>[
    _userJson(
      id: 1,
      loginId: 'primary-admin',
      role: 'admin',
      isActive: true,
      lastLoginAt: '2026-11-21T09:15:00Z',
    ),
    _userJson(id: 2, loginId: 'staff-user', role: 'viewer'),
  ];

  final logs = <Map<String, dynamic>>[
    {
      'id': 17,
      'user_id': 1,
      'login_id': 'primary-admin',
      'event_type': 'login_succeeded',
      'target': 'primary-admin',
      'created_at': '2026-11-21T09:15:00Z',
      'detail_json': '{"role":"admin"}',
    },
    {
      'id': 16,
      'user_id': 1,
      'login_id': 'primary-admin',
      'event_type': 'user_created',
      'target': 'staff-user',
      'created_at': '2026-11-20T11:15:00Z',
      'detail_json': '{"role":"viewer"}',
    },
  ];

  @override
  bool get hasAdminAccess => isAdmin;

  @override
  Future<CachedDataResult<T>> fetchMapParsed<T>(
    String endpoint, {
    Map<String, Object?>? params,
    required T Function(Map<String, dynamic> json) parser,
    Duration cacheTtl = const Duration(minutes: 30),
    bool allowStaleOnError = true,
    ApiCachePolicy? cachePolicy,
  }) async {
    reads.add((
      endpoint: endpoint,
      params: params == null ? null : Map<String, Object?>.of(params),
    ));
    if (endpoint == '/api/auth/users' && failUserFetch) {
      throw const ApiException('사용자 목록 조회 실패', statusCode: 503);
    }
    final Map<String, dynamic> json;
    if (endpoint == '/api/auth/users') {
      json = {'users': emptyResponses ? <dynamic>[] : users};
    } else if (endpoint == '/api/auth/audit-logs') {
      json = {'logs': emptyResponses ? <dynamic>[] : logs};
    } else {
      throw StateError('Unexpected GET $endpoint');
    }
    return CachedDataResult<T>(
      data: parser(json),
      fromCache: false,
      cachedAt: DateTime.utc(2026, 11, 22),
    );
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String endpoint, {
    Map<String, dynamic>? body,
    String method = 'POST',
  }) async {
    writes.add((
      endpoint: endpoint,
      method: method,
      body: body == null ? null : Map<String, dynamic>.of(body),
    ));
    final error = writeError;
    if (error != null) {
      throw error;
    }
    if (endpoint == '/api/auth/users' && body != null) {
      users.add(
        _userJson(
          id: 3,
          loginId: body['login_id'] as String,
          role: body['role'] as String,
        ),
      );
    } else if (endpoint.startsWith('/api/auth/users/') && body != null) {
      final id = int.parse(endpoint.split('/').last);
      final user = users.firstWhere((item) => item['id'] == id);
      user['role'] = body['role'];
      user['is_active'] = body['is_active'] == true ? 1 : 0;
      user['updated_at'] = '2026-11-22T10:00:00Z';
    }
    return const <String, dynamic>{'ok': true};
  }
}

Map<String, dynamic> _userJson({
  required int id,
  required String loginId,
  required String role,
  bool isActive = true,
  String? lastLoginAt,
}) =>
    {
      'id': id,
      'login_id': loginId,
      'role': role,
      'is_active': isActive ? 1 : 0,
      'failed_attempts': 0,
      'locked_until': null,
      'last_login_at': lastLoginAt,
      'created_at': '2026-11-01T00:00:00Z',
      'updated_at': '2026-11-01T00:00:00Z',
    };

Widget _app(_AdminUsersAppState state) {
  return ChangeNotifierProvider<AppState>.value(
    value: state,
    child: const MaterialApp(home: AdminUsersScreen()),
  );
}

Future<void> _scrollToVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    400,
    scrollable: find.byType(Scrollable).first,
  );
}

Future<void> _scrollToTop(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  tester.state<ScrollableState>(scrollable).position.jumpTo(0);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('requires admin access and makes no API requests for other roles',
      (tester) async {
    final state = _AdminUsersAppState()..isAdmin = false;
    addTearDown(state.dispose);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    expect(find.text('권한 없음: 관리자 권한이 필요합니다.'), findsOneWidget);
    expect(state.reads, isEmpty);
    expect(find.text('primary-admin'), findsNothing);
  });

  testWidgets('loads current user and audit shapes and filters recent logs',
      (tester) async {
    final state = _AdminUsersAppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    expect(
      state.reads.map((read) => read.endpoint),
      containsAll(['/api/auth/users', '/api/auth/audit-logs']),
    );
    final userRead =
        state.reads.firstWhere((read) => read.endpoint == '/api/auth/users');
    expect(userRead.params, isNull);
    expect(
      state.reads
          .firstWhere((read) => read.endpoint == '/api/auth/audit-logs')
          .params,
      {'limit': 30},
    );
    expect(find.text('primary-admin'), findsWidgets);
    expect(find.text('staff-user'), findsWidgets);

    final filter = find.byKey(const ValueKey('admin-users-audit-filter'));
    await _scrollToVisible(tester, filter);
    await tester.enterText(filter, 'user_created');
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == 'user_created',
      ),
      findsOneWidget,
    );
    expect(find.text('login_succeeded'), findsNothing);
    expect(state.reads, hasLength(2));
  });

  testWidgets('shows empty states for empty user and audit responses',
      (tester) async {
    final state = _AdminUsersAppState()..emptyResponses = true;
    addTearDown(state.dispose);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    expect(find.text('등록된 사용자가 없습니다.'), findsOneWidget);
    final auditPanel = find.text('최근 감사 로그');
    await _scrollToVisible(tester, auditPanel);
    expect(find.text('감사 로그가 없습니다.'), findsOneWidget);
  });

  testWidgets('rejects invalid credentials before opening confirmation',
      (tester) async {
    final state = _AdminUsersAppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('admin-users-login-id')),
      'new-staff',
    );
    await _scrollToVisible(
      tester,
      find.byKey(const ValueKey('admin-users-initial-password')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('admin-users-initial-password')),
      'too-short',
    );

    final create = find.byKey(const ValueKey('admin-users-create'));
    await _scrollToVisible(tester, create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(state.writes, isEmpty);
    await _scrollToTop(tester);
    expect(find.text('비밀번호는 최소 12자 이상이어야 합니다.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin-user-create-confirm')),
      findsNothing,
    );
  });

  testWidgets(
      'requires confirmation before creating and sends supported payload',
      (tester) async {
    final state = _AdminUsersAppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    await _scrollToVisible(
      tester,
      find.byKey(const ValueKey('admin-users-login-id')),
    );
    const password = 'test-only-password-2026';
    await tester.enterText(
      find.byKey(const ValueKey('admin-users-login-id')),
      '  new-staff  ',
    );
    await _scrollToVisible(
      tester,
      find.byKey(const ValueKey('admin-users-initial-password')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('admin-users-initial-password')),
      password,
    );
    final create = find.byKey(const ValueKey('admin-users-create'));
    await _scrollToVisible(tester, create);
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(state.writes, isEmpty);
    final confirmationDialog = find.ancestor(
      of: find.byKey(const ValueKey('admin-user-create-confirm')),
      matching: find.byType(AlertDialog),
    );
    expect(
      find.descendant(
        of: confirmationDialog,
        matching: find.textContaining('new-staff'),
      ),
      findsOneWidget,
    );
    expect(find.text(password), findsNothing);
    await tester.tap(find.byKey(const ValueKey('admin-user-create-confirm')));
    await tester.pumpAndSettle();

    expect(state.writes, hasLength(1));
    expect(state.writes.single.endpoint, '/api/auth/users');
    expect(state.writes.single.method, 'POST');
    expect(state.writes.single.body, {
      'login_id': 'new-staff',
      'password': password,
      'role': 'viewer',
    });
    expect(find.text(password), findsNothing);
    expect(find.text('new-staff'), findsWidgets);
  });

  testWidgets(
      'requires confirmation before PATCHing a user role and active state',
      (tester) async {
    final state = _AdminUsersAppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    final role = find.byKey(const ValueKey('admin-user-role-2'));
    await _scrollToVisible(tester, role);
    await tester.tap(role);
    await tester.pumpAndSettle();
    await tester.tap(find.text('운영자').last);
    await tester.pumpAndSettle();

    final active = find.byKey(const ValueKey('admin-user-active-2'));
    await _scrollToVisible(tester, active);
    await tester.tap(active);
    await tester.pumpAndSettle();

    final save = find.byKey(const ValueKey('admin-user-save-2'));
    await _scrollToVisible(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(state.writes, isEmpty);

    await tester.tap(find.byKey(const ValueKey('admin-user-update-confirm')));
    await tester.pumpAndSettle();

    expect(state.writes, hasLength(1));
    expect(state.writes.single.endpoint, '/api/auth/users/2');
    expect(state.writes.single.method, 'PATCH');
    expect(state.writes.single.body, {
      'role': 'operator',
      'is_active': false,
    });
  });

  testWidgets('confirms password reset and does not display the new password',
      (tester) async {
    final state = _AdminUsersAppState();
    addTearDown(state.dispose);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    const password = 'test-only-password-2028';
    final passwordField =
        find.byKey(const ValueKey('admin-user-password-2'));
    await _scrollToVisible(tester, passwordField);
    await tester.enterText(passwordField, password);
    final save = find.byKey(const ValueKey('admin-user-save-2'));
    await _scrollToVisible(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(state.writes, isEmpty);
    expect(find.text(password), findsNothing);
    await tester.tap(find.byKey(const ValueKey('admin-user-update-confirm')));
    await tester.pumpAndSettle();

    expect(state.writes, hasLength(1));
    expect(state.writes.single.endpoint, '/api/auth/users/2');
    expect(state.writes.single.method, 'PATCH');
    expect(state.writes.single.body, {
      'role': 'viewer',
      'is_active': true,
      'new_password': password,
    });
    expect(find.text(password), findsNothing);
  });

  testWidgets('shows duplicate conflict without echoing password',
      (tester) async {
    final state = _AdminUsersAppState()
      ..writeError =
          const ApiException('이미 존재하는 아이디입니다.', statusCode: 409);
    addTearDown(state.dispose);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    await _scrollToVisible(
      tester,
      find.byKey(const ValueKey('admin-users-login-id')),
    );
    const password = 'test-only-password-2027';
    await tester.enterText(
      find.byKey(const ValueKey('admin-users-login-id')),
      'duplicate-user',
    );
    await _scrollToVisible(
      tester,
      find.byKey(const ValueKey('admin-users-initial-password')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('admin-users-initial-password')),
      password,
    );
    final create = find.byKey(const ValueKey('admin-users-create'));
    await _scrollToVisible(tester, create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin-user-create-confirm')));
    await tester.pumpAndSettle();

    await _scrollToTop(tester);
    expect(find.textContaining('계정 충돌'), findsOneWidget);
    expect(find.textContaining('이미 존재하는 아이디입니다.'), findsOneWidget);
    expect(find.text(password), findsNothing);
  });

  testWidgets('shows retry state when users endpoint fails',
      (tester) async {
    final state = _AdminUsersAppState()..failUserFetch = true;
    addTearDown(state.dispose);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    expect(find.textContaining('사용자 목록 조회 실패'), findsOneWidget);
    expect(find.text('다시 불러오기'), findsOneWidget);
    expect(state.reads.where((read) => read.endpoint == '/api/auth/users'),
        hasLength(1));

    state.failUserFetch = false;
    final retry = find.text('다시 불러오기');
    await _scrollToVisible(tester, retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(state.reads.where((read) => read.endpoint == '/api/auth/users'),
        hasLength(2));
    expect(find.text('staff-user'), findsOneWidget);
  });
}
