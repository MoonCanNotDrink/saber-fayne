import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextcloud/core.dart';
import 'package:saber/components/nextcloud/test_apk_login_dialog.dart';
import 'package:saber/data/nextcloud/login_flow.dart';

void main() {
  test('external-browser exception belongs only to Android stylusTest', () {
    for (final flavor in [null, '', 'production', 'stylusTest']) {
      for (final android in [false, true]) {
        expect(
          SaberLoginFlow.isTestBrowserFlavor(android: android, flavor: flavor),
          android && flavor == 'stylusTest',
        );
      }
    }
  });

  testWidgets('uses unchanged v2 endpoints and returns existing credentials', (
    tester,
  ) async {
    final fake = _FakeLoginServer()..approved = true;
    final flow = fake.start(tester);
    final result = _result(flow);
    await tester.pump();

    final value = await result;
    expect(value, isA<LoginFlowV2Credentials>());
    final credentials = value as LoginFlowV2Credentials;
    expect(fake.paths, ['/index.php/login/v2', '/index.php/login/v2/poll']);
    expect(fake.browserUrls, [Uri.parse(_FakeLoginServer.loginUrl)]);
    expect(credentials.server, 'https://nextcloud.invalid');
    expect(credentials.loginName, 'test-user');
    expect(credentials.appPassword, 'mock-app-password');
    expect(fake.closed, isTrue);
    await tester.pump(const Duration(minutes: 6));
    expect(fake.polls, 1);
    flow.dispose();
  });

  testWidgets(
    'browser closure leaves approval pending with reopen and cancel',
    (tester) async {
      final fake = _FakeLoginServer();
      final flow = fake.start(tester);
      final result = _result(flow);
      await tester.pump();
      expect(fake.polls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 3));
      expect(fake.polls, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(fake.polls, 2);
      expect(flow.completer.isCompleted, isFalse);
      await flow.openLoginUrl();
      expect(fake.browserUrls, hasLength(2));
      flow.dispose();
      expect(await result, isA<TestApkLoginCancelled>());
      await tester.pump(const Duration(seconds: 2));
      expect(fake.polls, 2);
      expect(fake.closed, isTrue);
    },
  );

  testWidgets('background approval is collected when the app resumes', (
    tester,
  ) async {
    final fake = _FakeLoginServer();
    final flow = fake.start(tester);
    final result = _result(flow);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    fake.approved = true;
    await tester.pump(const Duration(seconds: 10));
    expect(flow.completer.isCompleted, isFalse);
    expect(fake.polls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(await result, isA<LoginFlowV2Credentials>());
    expect(fake.polls, 2);
  });

  testWidgets(
    'deadline expires while backgrounded without persisting a token',
    (tester) async {
      final fake = _FakeLoginServer();
      final flow = fake.start(tester, timeout: const Duration(seconds: 5));
      final result = _result(flow);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 5));
      expect(await result, isA<TimeoutException>());
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(fake.polls, 1);
      expect(fake.closed, isTrue);
    },
  );

  testWidgets('cancelling before init completes never opens the browser', (
    tester,
  ) async {
    final fake = _FakeLoginServer()..pendingInit = Completer<void>();
    final flow = fake.start(tester);
    final result = _result(flow);
    await tester.pump();
    flow.dispose();
    fake.pendingInit!.complete();
    await tester.pump();
    expect(await result, isA<TestApkLoginCancelled>());
    expect(fake.browserUrls, isEmpty);
    expect(fake.polls, 0);
  });

  testWidgets('timeout during init ignores the late login URL', (tester) async {
    final fake = _FakeLoginServer()..pendingInit = Completer<void>();
    final flow = fake.start(tester, timeout: const Duration(seconds: 5));
    final result = _result(flow);
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    expect(await result, isA<TimeoutException>());
    expect(fake.closed, isTrue);
    fake.pendingInit!.complete();
    await tester.pump();
    expect(fake.browserUrls, isEmpty);
    expect(fake.polls, 0);
  });

  testWidgets('detaching cancels the session and closes the client', (
    tester,
  ) async {
    final fake = _FakeLoginServer();
    final flow = fake.start(tester);
    final result = _result(flow);
    await tester.pump();
    expect(fake.polls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.detached);
    await tester.pump();
    expect(await result, isA<TestApkLoginCancelled>());
    expect(fake.closed, isTrue);
    fake.approved = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 2));
    expect(fake.polls, 1);
  });

  testWidgets('cancelling an in-flight poll ignores its late credentials', (
    tester,
  ) async {
    final fake = _FakeLoginServer()
      ..pendingPoll = Completer<void>()
      ..approved = true;
    final flow = fake.start(tester);
    final result = _result(flow);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(fake.polls, 1, reason: 'Polling requests must not overlap');
    flow.dispose();
    fake.pendingPoll!.complete();
    await tester.pump();
    expect(await result, isA<TestApkLoginCancelled>());
  });

  testWidgets('browser launch failure terminates polling', (tester) async {
    final fake = _FakeLoginServer()..browserOpens = false;
    final flow = fake.start(tester);
    final result = _result(flow);
    await tester.pump();
    expect(await result, isA<StateError>());
    expect(fake.polls, 0);
    expect(fake.closed, isTrue);
  });

  testWidgets('a stalled request times out and closes the client', (
    tester,
  ) async {
    final fake = _FakeLoginServer()..pendingPoll = Completer<void>();
    final flow = fake.start(tester);
    final result = _result(flow);
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(await result, isA<TimeoutException>());
    expect(fake.closed, isTrue);
    fake.pendingPoll!.complete();
    await tester.pump();
  });

  testWidgets('test dialog cancels once and returns to the login page', (
    tester,
  ) async {
    final fake = _FakeLoginServer();
    final flow = fake.start(tester);
    final result = _result(flow);
    await _showDialog(tester, flow);
    expect(find.text('Test APK login'), findsOneWidget);
    await tester.tap(find.text('Cancel login'));
    await tester.pumpAndSettle();
    expect(await result, isA<TestApkLoginCancelled>());
    expect(find.text('Login page'), findsOneWidget);
    expect(find.byType(TestApkLoginDialog), findsNothing);
  });

  testWidgets('successful approval closes the dialog exactly once', (
    tester,
  ) async {
    final fake = _FakeLoginServer();
    final flow = fake.start(tester);
    final result = _result(flow);
    final observer = _CountingNavigatorObserver();
    await _showDialog(tester, flow, observer: observer);
    expect(find.byType(TestApkLoginDialog), findsOneWidget);
    fake.approved = true;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(await result, isA<LoginFlowV2Credentials>());
    expect(observer.pops, 1);
    expect(find.byType(TestApkLoginDialog), findsNothing);
    expect(find.text('Login page'), findsOneWidget);
    flow.dispose();
    await tester.pump(const Duration(minutes: 6));
    expect(observer.pops, 1);
    expect(find.text('Login page'), findsOneWidget);
  });

  testWidgets('Android system Back cancels and closes the dialog once', (
    tester,
  ) async {
    final fake = _FakeLoginServer();
    final flow = fake.start(tester);
    final result = _result(flow);
    final observer = _CountingNavigatorObserver();
    await _showDialog(tester, flow, observer: observer);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(await result, isA<TestApkLoginCancelled>());
    expect(observer.pops, 1);
    expect(fake.closed, isTrue);
    expect(find.byType(TestApkLoginDialog), findsNothing);
    expect(find.text('Login page'), findsOneWidget);
  });

  testWidgets(
    'test dialog reports timeout without exposing a server response',
    (tester) async {
      final fake = _FakeLoginServer();
      final flow = fake.start(tester, timeout: const Duration(seconds: 5));
      final result = _result(flow);
      await _showDialog(tester, flow);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(await result, isA<TimeoutException>());
      expect(
        find.text('Login timed out. Close this dialog and start login again.'),
        findsOneWidget,
      );
      expect(find.text('Reopen browser'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Login page'), findsOneWidget);
    },
  );
}

Future<Object> _result(SaberLoginFlow flow) => flow.future.then<Object>(
  (value) => value,
  onError: (Object error, StackTrace _) => error,
);

Future<void> _showDialog(
  WidgetTester tester,
  SaberLoginFlow flow, {
  NavigatorObserver? observer,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [?observer],
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => TestApkLoginDialog(loginFlow: flow),
            ),
            child: const Text('Login page'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Login page'));
  await tester.pumpAndSettle();
}

class _CountingNavigatorObserver extends NavigatorObserver {
  var pops = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    ++pops;
    super.didPop(route, previousRoute);
  }
}

class _FakeLoginServer {
  static const loginUrl = 'https://nextcloud.invalid/login/approve-fake-token';
  final paths = <String>[];
  final browserUrls = <Uri>[];
  var approved = false;
  var browserOpens = true;
  var polls = 0;
  var closed = false;
  Completer<void>? pendingInit;
  Completer<void>? pendingPoll;

  SaberLoginFlow start(
    WidgetTester tester, {
    Duration timeout = const Duration(minutes: 5),
  }) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    return SaberLoginFlow.forTesting(
      serverUrl: Uri.parse('https://nextcloud.invalid'),
      client: _TrackedMockClient(_handle, () => closed = true),
      openBrowser: (uri) async {
        browserUrls.add(uri);
        return browserOpens;
      },
      timeout: timeout,
    );
  }

  Future<http.Response> _handle(http.Request request) async {
    expectSync(request.method.toUpperCase(), 'POST');
    expectSync(request.url.host, 'nextcloud.invalid');
    paths.add(request.url.path);
    if (request.url.path == '/index.php/login/v2') {
      await pendingInit?.future;
      return _json({
        'poll': {
          'token': 'mock-poll-token',
          'endpoint': 'https://nextcloud.invalid/index.php/login/v2/poll',
        },
        'login': loginUrl,
      });
    }
    expectSync(request.url.path, '/index.php/login/v2/poll');
    expectSync(jsonDecode(request.body), {'token': 'mock-poll-token'});
    ++polls;
    await pendingPoll?.future;
    if (!approved) return http.Response('', 404);
    return _json({
      'server': 'https://nextcloud.invalid',
      'loginName': 'test-user',
      'appPassword': 'mock-app-password',
    });
  }

  http.Response _json(Map<String, Object> body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

class _TrackedMockClient extends MockClient {
  new(super.fn, this.onClose);
  final VoidCallback onClose;

  @override
  void close() {
    onClose();
    super.close();
  }
}
