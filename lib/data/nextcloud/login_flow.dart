import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:nextcloud/core.dart';
import 'package:nextcloud/nextcloud.dart';
import 'package:saber/data/nextcloud/nc_http_overrides.dart';
import 'package:saber/data/nextcloud/nextcloud_client_extension.dart';
import 'package:url_launcher/url_launcher.dart';

class SaberLoginFlow with WidgetsBindingObserver {
  new start({required this.serverUrl})
    : _clientOverride = null,
      _browserOverride = null,
      _testBrowserOverride = null,
      _testTimeout = const Duration(minutes: 5) {
    NcHttpOverrides.tempAcceptBadCertificateFrom(serverUrl);
    _startTestBrowserSession();
    unawaited(_run());
  }

  /// Creates a login flow with local fake transports, without using an account.
  @visibleForTesting
  new forTesting({
    required this.serverUrl,
    required http.Client client,
    required Future<bool> Function(Uri) openBrowser,
    bool testBrowser = true,
    Duration timeout = const Duration(minutes: 5),
  }) : _clientOverride = client,
       _browserOverride = openBrowser,
       _testBrowserOverride = testBrowser,
       _testTimeout = timeout {
    _startTestBrowserSession();
    unawaited(_run());
  }

  final Uri serverUrl;
  final http.Client? _clientOverride;
  final Future<bool> Function(Uri)? _browserOverride;
  final bool? _testBrowserOverride;
  final Duration _testTimeout;

  /// Only the separately installed Android test flavor uses an external browser.
  bool get usesTestBrowserLogin =>
      _testBrowserOverride ??
      isTestBrowserFlavor(android: Platform.isAndroid, flavor: appFlavor);

  @visibleForTesting
  static bool isTestBrowserFlavor({required bool android, String? flavor}) =>
      android && flavor == 'stylusTest';

  final log = Logger('SaberLoginFlow');
  Timer? _pollTimer;
  Timer? _testTimeoutTimer;
  DateTime? _testDeadline;
  Future<void> Function()? _poll;
  http.Client? _testClient;
  var _testForeground = true;
  var _testPolling = false;
  var _openingBrowser = false;

  final completer = Completer<LoginFlowV2Credentials>();
  late final future = completer.future;

  LoginFlowV2? init;

  Future<void> openLoginUrl() async {
    final init = this.init;
    if (init == null) return;

    if (usesTestBrowserLogin) {
      if (completer.isCompleted || _openingBrowser) return;
      _openingBrowser = true;
      try {
        final uri = Uri.parse(init.login);
        final opened =
            await (_browserOverride?.call(uri) ??
                launchUrl(uri, mode: LaunchMode.externalApplication));
        if (!opened) throw StateError('Could not open the login browser');
      } catch (error, stackTrace) {
        _finishTestError(error, stackTrace);
      } finally {
        _openingBrowser = false;
      }
      return;
    }

    if (Platform.isMacOS || Platform.isIOS || Platform.isAndroid) {
      // Use FlutterWebAuth2 which returns to Saber when authenticated
      log.info('Opening login link in-app: ${init.login}');
      await FlutterWebAuth2.authenticate(
        url: init.login,
        callbackUrlScheme: 'nc',
      );
    } else {
      // Use url_launcher to open the link in the default browser
      log.info('Opening login link in browser: ${init.login}');
      final loginLink = Uri.parse(init.login);
      await launchUrl(loginLink);
    }
  }

  Future<void> _run() async {
    Future<void> start() async {
      final httpClient =
          _clientOverride ?? NextcloudClientExtension.newHttpClient();
      if (usesTestBrowserLogin) _testClient = httpClient;
      final client = NextcloudClient(serverUrl, httpClient: httpClient);
      final flowClient = client.core.clientFlowLoginV2;
      init = await flowClient.init().then((response) => response.body);
      if (usesTestBrowserLogin) {
        if (completer.isCompleted) return;
      } else {
        log.info('init: $init');
      }

      // Both APKs use the same server-side Login Flow v2 poll and credentials.
      Future<void> poll() async {
        final response = await flowClient.poll(
          $body: ClientFlowLoginV2PollRequestApplicationJson(
            (b) => b..token = init!.poll.token,
          ),
        );
        _pollTimer?.cancel();
        if (!completer.isCompleted) completer.complete(response.body);
        if (usesTestBrowserLogin) _stopTestBrowserSession();
      }

      if (usesTestBrowserLogin) {
        _poll = poll;
        await openLoginUrl();
        _resumeTestPolling();
        return;
      }

      openLoginUrl();
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _catch404Error(poll),
      );
    }

    if (usesTestBrowserLogin) {
      try {
        await start();
      } catch (error, stackTrace) {
        _finishTestError(error, stackTrace);
      }
    } else {
      _catchHttpError(start);
    }
  }

  void _startTestBrowserSession() {
    if (!usesTestBrowserLogin) return;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _testForeground = state == null || state == AppLifecycleState.resumed;
    _testDeadline = DateTime.now().add(_testTimeout);
    _testTimeoutTimer = Timer(_testTimeout, _timeoutTestSession);
  }

  void _timeoutTestSession() => _finishTestError(
    TimeoutException('Test APK login timed out. Start login again.'),
    StackTrace.current,
  );

  void _resumeTestPolling() {
    if (!_testForeground || completer.isCompleted || _poll == null) return;
    if (!DateTime.now().isBefore(_testDeadline!)) {
      _timeoutTestSession();
      return;
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _pollTestSession(),
    );
    unawaited(_pollTestSession());
  }

  Future<void> _pollTestSession() async {
    if (!_testForeground || _testPolling || completer.isCompleted) return;
    _testPolling = true;
    try {
      // A pending approval is HTTP 404, exactly as in the production flow.
      await _catch404Error(_poll!).timeout(const Duration(seconds: 30));
    } catch (error, stackTrace) {
      _finishTestError(error, stackTrace);
    } finally {
      _testPolling = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!usesTestBrowserLogin || completer.isCompleted) return;
    _testForeground = state == AppLifecycleState.resumed;
    if (_testForeground) {
      _resumeTestPolling();
    } else {
      _pollTimer?.cancel();
      if (state == AppLifecycleState.detached) dispose();
    }
  }

  void _finishTestError(Object error, StackTrace stackTrace) {
    if (completer.isCompleted) return;
    _stopTestBrowserSession();
    completer.completeError(error, stackTrace);
  }

  void _stopTestBrowserSession() {
    _pollTimer?.cancel();
    _testTimeoutTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _testClient?.close();
  }

  Future<T?> _catchHttpError<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on http.ClientException catch (error, stackTrace) {
      log.severe('Error while polling the login flow.', error, stackTrace);
      if (!completer.isCompleted) completer.completeError(error, stackTrace);
      return null;
    }
  }

  Future<T?> _catch404Error<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } on DynamiteStatusCodeException catch (error) {
      if (error.statusCode != 404) rethrow;

      log.fine('Login flow not found or completed yet, will repoll');
      return null;
    }
  }

  /// Cancels the polling timer and completes the [completer] with an error.
  ///
  /// This is idempotent and is safe to call multiple times.
  void dispose() {
    if (usesTestBrowserLogin) {
      _finishTestError(const TestApkLoginCancelled(), StackTrace.current);
      return;
    }
    _pollTimer?.cancel();
    if (!completer.isCompleted)
      completer.completeError(TimeoutException('Login flow was disposed'));
  }
}

/// The user cancelled this test APK's pending browser approval.
class TestApkLoginCancelled implements Exception {
  const new();
}
