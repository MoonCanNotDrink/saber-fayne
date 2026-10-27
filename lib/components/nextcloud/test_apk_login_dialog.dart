import 'dart:async';

import 'package:flutter/material.dart';
import 'package:saber/data/nextcloud/login_flow.dart';

/// Browser approval controls used only by the separately installed test APK.
class TestApkLoginDialog extends StatefulWidget {
  const new({super.key, required this.loginFlow});

  final SaberLoginFlow loginFlow;

  @override
  State<TestApkLoginDialog> createState() => _TestApkLoginDialogState();
}

class _TestApkLoginDialogState extends State<TestApkLoginDialog> {
  String? _error;
  var _closing = false;

  @override
  void initState() {
    super.initState();
    widget.loginFlow.future.then(
      (_) => _close(),
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted || _closing) return;
        if (error is TestApkLoginCancelled) {
          _close();
          return;
        }
        setState(() {
          _error = error is TimeoutException
              ? 'Login timed out. Close this dialog and start login again.'
              : 'Login could not finish. Close this dialog and try again.';
        });
      },
    );
  }

  void _close() {
    if (!mounted || _closing) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  void _cancel() {
    widget.loginFlow.dispose();
    _close();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _cancel();
    },
    child: AlertDialog(
      title: const Text('Test APK login'),
      content: Text(
        _error ??
            'Approve login in your browser, then return to this app. '
                'Closing the browser does not finish or cancel login. '
                'You can reopen it or cancel here. Login expires after five minutes.',
      ),
      actions: [
        if (_error == null)
          TextButton(
            onPressed: widget.loginFlow.openLoginUrl,
            child: const Text('Reopen browser'),
          ),
        TextButton(
          onPressed: _cancel,
          child: Text(_error == null ? 'Cancel login' : 'Close'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    widget.loginFlow.dispose();
    super.dispose();
  }
}
