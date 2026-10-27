import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/canvas_gesture_detector.dart';
import 'package:saber/data/file_manager/file_manager.dart';
import 'package:saber/data/flavor_config.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/tools/pen.dart';
import 'package:saber/pages/editor/editor.dart';

import 'utils/test_mock_channel_handlers.dart';

void main() {
  test('Stylus priority is off by default', () {
    expect(stows.stylusPriority.value, isFalse);
  });

  group('Stylus', () {
    FlavorConfig.setup();
    FileManager.documentsDirectory =
        '$tmpDir/stylus_test/'
        '${FileManager.appRootDirectoryPrefix}';
    stows.editorFingerDrawing.value = false;

    for (final priority in [false, true]) {
      group('priority=$priority', () {
        setUp(() {
          stows.stylusPriority.value = priority;
          stows.editorFingerDrawing.value = false;
        });
        tearDown(() {
          stows.stylusPriority.value = false;
        });
        // Fast strokes may have no preceding hover event.
        for (final withHover in [true, false]) {
          _platformTestWidgets(
            'Normal input should draw a stroke (hover=$withHover)',
            (tester) async {
              final editorState = await tester._pumpEditor();
              await tester.pump();
              final page = editorState.coreInfo.pages.first;
              expect(page.strokes, isEmpty);
              await tester._stylusDrag(editorState, withHover);
              expect(page.strokes, hasLength(1));
            },
          );

          // Styluses like the S Pen use a button to trigger the eraser.
          _platformTestWidgets(
            'Pressing the stylus button should erase (hover=$withHover)',
            (tester) async {
              final editorState = await tester._pumpEditor();
              await tester.pump();
              final page = editorState.coreInfo.pages.first;
              await tester._stylusDrag(editorState, withHover);
              expect(page.strokes, hasLength(1));
              await tester._stylusDrag(
                editorState,
                withHover,
                buttons: kSecondaryButton,
              );
              expect(page.strokes, hasLength(0));
            },
          );

          // Styluses like the Noris Digital Jumbo have an eraser on the bottom.
          _platformTestWidgets(
            'Inverse stylus should erase (hover=$withHover)',
            (tester) async {
              final editorState = await tester._pumpEditor();
              await tester.pump();
              final page = editorState.coreInfo.pages.first;
              await tester._stylusDrag(editorState, withHover);
              expect(page.strokes, hasLength(1));
              await tester._stylusDrag(
                editorState,
                withHover,
                kind: .invertedStylus,
              );
              expect(page.strokes, hasLength(0));
            },
          );
        }
      });
    }
  });

  group('Stylus priority editor integration', () {
    setUp(() {
      stows.stylusPriority.value = true;
      stows.editorFingerDrawing.value = false;
    });
    tearDown(() {
      stows.stylusPriority.value = false;
    });

    _platformTestWidgets('palm movement and release preserve pen pressure', (
      tester,
    ) async {
      final editor = await tester._pumpEditor();
      await tester.pump();
      final center = tester.getCenter(find.byType(CanvasGestureDetector));
      final pen = await tester.createGesture(pointer: 77, kind: .stylus);
      await pen.downWithCustomEvent(
        center,
        PointerDownEvent(
          pointer: 77,
          kind: .stylus,
          position: center,
          pressure: 0.6,
          pressureMin: 0,
          pressureMax: 1,
          buttons: kPrimaryButton,
        ),
      );
      await pen.updateWithCustomEvent(
        PointerMoveEvent(
          pointer: 77,
          kind: .stylus,
          position: center + const Offset(40, 0),
          delta: const Offset(40, 0),
          pressure: 0.8,
          pressureMin: 0,
          pressureMax: 1,
          buttons: kPrimaryButton,
        ),
      );
      final palm = await tester.startGesture(center + const Offset(0, 80));
      await palm.moveBy(const Offset(100, 30));
      expect(editor.currentPointerKind, PointerDeviceKind.stylus);
      expect(editor.currentPressure, 0.8);
      await palm.up();
      expect(editor.currentPointerKind, PointerDeviceKind.stylus);
      expect(editor.currentPressure, 0.8);
      await pen.updateWithCustomEvent(
        PointerMoveEvent(
          pointer: 77,
          kind: .stylus,
          position: center + const Offset(60, 10),
          delta: const Offset(20, 10),
          pressure: 0.3,
          pressureMin: 0,
          pressureMax: 1,
          buttons: kPrimaryButton,
        ),
      );
      expect(editor.currentPressure, 0.3);
      await pen.up();
      expect(editor.coreInfo.pages.first.strokes, hasLength(1));
    });

    _platformTestWidgets(
      'pen takes over a two-finger gesture without waiting',
      (tester) async {
        final editor = await tester._pumpEditor();
        await tester.pump();
        final center = tester.getCenter(find.byType(CanvasGestureDetector));
        final first = await tester.startGesture(center);
        final second = await tester.startGesture(center + const Offset(60, 0));
        await first.moveBy(const Offset(0, -40));
        await second.moveBy(const Offset(40, -40));
        expect(editor.lastSeenPointerCount, 2);
        final pen = await tester.startGesture(center, kind: .stylus);
        await pen.moveBy(const Offset(40, 10));
        await pen.moveBy(const Offset(20, 10));
        await first.moveBy(const Offset(100, 100));
        await second.up();
        await pen.up();
        await first.up();
        expect(
          editor.coreInfo.pages.expand((page) => page.strokes),
          hasLength(1),
        );
      },
    );

    _platformTestWidgets(
      'takeover discards only the unfinished finger stroke',
      (tester) async {
        final editor = await tester._pumpEditor();
        await tester.pump();
        stows.editorFingerDrawing.value = true;
        final center = tester.getCenter(find.byType(CanvasGestureDetector));
        final palm = await tester.startGesture(center);
        await palm.moveBy(const Offset(40, 10));
        await palm.moveBy(const Offset(30, 10));
        final pen = await tester.startGesture(center, kind: .stylus);
        await pen.moveBy(const Offset(40, -10));
        await pen.moveBy(const Offset(30, -10));
        await pen.up();
        await palm.up();
        expect(editor.coreInfo.pages.first.strokes, hasLength(1));
      },
    );

    for (final kind in [
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
    ]) {
      _platformTestWidgets(
        '$kind eraser hover cancels the pending finger stroke',
        (tester) async {
          final editor = await tester._pumpEditor();
          await tester.pump();
          stows.editorFingerDrawing.value = true;
          final center = tester.getCenter(find.byType(CanvasGestureDetector));
          final palm = await tester.startGesture(center);
          await palm.moveBy(const Offset(40, 10));
          await palm.moveBy(const Offset(30, 10));
          expect(Pen.currentStroke, isNotNull);
          await tester.sendEventToBinding(
            PointerHoverEvent(
              kind: kind,
              position: center,
              buttons: kSecondaryButton,
            ),
          );
          expect(Pen.currentStroke, isNull);
          expect(editor.coreInfo.pages.first.strokes, isEmpty);
          await palm.up();
          await tester._stylusDrag(
            editor,
            false,
            kind: kind,
            buttons: kSecondaryButton,
          );
          expect(editor.coreInfo.pages.first.strokes, isEmpty);
          await tester._stylusDrag(editor, false);
          expect(editor.coreInfo.pages.first.strokes, hasLength(1));
        },
      );
    }

    _platformTestWidgets(
      'palm release does not release the stylus eraser button',
      (tester) async {
        final editor = await tester._pumpEditor();
        await tester.pump();
        await tester._stylusDrag(editor, false);
        final center = tester.getCenter(find.byType(CanvasGestureDetector));
        final eraser = await tester.startGesture(
          center,
          kind: .stylus,
          buttons: kSecondaryButton,
        );
        await eraser.moveBy(const Offset(40, 10));
        final palm = await tester.startGesture(center + const Offset(0, 80));
        await palm.up();
        expect(editor.stylusButtonWasPressed, isTrue);
        await eraser.moveBy(const Offset(-20, -10));
        await eraser.up();
        expect(editor.coreInfo.pages.first.strokes, isEmpty);
      },
    );

    for (final kind in [
      PointerDeviceKind.stylus,
      PointerDeviceKind.invertedStylus,
    ]) {
      _platformTestWidgets(
        'binding cancellation clears $kind pressure and button',
        (tester) async {
          final editor = await tester._pumpEditor();
          await tester.pump();
          final canvasFinder = find.byType(CanvasGestureDetector);
          final canvas = tester.state<CanvasGestureDetectorState>(canvasFinder);
          final center = tester.getCenter(canvasFinder);
          final pen = await tester.createGesture(
            pointer: 81,
            kind: kind,
            buttons: kSecondaryButton,
          );
          await pen.downWithCustomEvent(
            center,
            PointerDownEvent(
              pointer: 81,
              kind: kind,
              position: center,
              pressure: 0.7,
              pressureMin: 0,
              pressureMax: 1,
              buttons: kSecondaryButton,
            ),
          );
          expect(canvas.stylusButtonWasPressed, isTrue);
          expect(editor.currentPressure, 0.7);
          // Binding-generated cancel has the default touch kind, unlike the pen.
          tester.binding.cancelPointer(81);
          await tester.pump();
          expect(canvas.stylusButtonWasPressed, isFalse);
          expect(editor.currentPressure, isNull);
          await tester._stylusDrag(editor, false);
          expect(editor.coreInfo.pages.first.strokes, hasLength(1));
        },
      );
    }

    _platformTestWidgets('cancelled pen and rapid strokes recover cleanly', (
      tester,
    ) async {
      final editor = await tester._pumpEditor();
      await tester.pump();
      final center = tester.getCenter(find.byType(CanvasGestureDetector));
      final cancelled = await tester.startGesture(center, kind: .stylus);
      await cancelled.moveBy(const Offset(40, 10));
      await cancelled.cancel();
      final countAfterCancel = editor.coreInfo.pages.first.strokes.length;
      await tester._stylusDrag(editor, false);
      await tester._stylusDrag(editor, false);
      expect(editor.coreInfo.pages.first.strokes.length, countAfterCancel + 2);
      await tester.pump(const Duration(milliseconds: 401));
      final scrollBefore = editor.scrollY;
      await tester.dragFrom(center, const Offset(0, -100));
      expect(editor.scrollY, isNot(scrollBefore));
      // The existing HUD hides itself five seconds after navigation.
      await tester.pump(const Duration(seconds: 6));
    });

    _platformTestWidgets(
      'resume finishes a pen stroke when the OS omits cancel',
      (tester) async {
        final editor = await tester._pumpEditor();
        await tester.pump();
        final center = tester.getCenter(find.byType(CanvasGestureDetector));
        final pen = await tester.startGesture(center, kind: .stylus);
        await pen.moveBy(const Offset(40, 10));
        await pen.moveBy(const Offset(30, 10));
        expect(Pen.currentStroke, isNotNull);
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pump();
        expect(Pen.currentStroke, isNull);
        final completed = editor.coreInfo.pages.first.strokes.length;
        await tester._stylusDrag(editor, false);
        expect(editor.coreInfo.pages.first.strokes.length, completed + 1);
      },
    );

    _platformTestWidgets('setting has no effect on desktop pointer behavior', (
      tester,
    ) async {
      final editor = await tester._pumpEditor();
      await tester.pump();
      final center = tester.getCenter(find.byType(CanvasGestureDetector));
      final pen = await tester.startGesture(center, kind: .stylus);
      final touch = await tester.startGesture(center + const Offset(50, 0));
      await pen.moveBy(const Offset(40, 10));
      await touch.moveBy(const Offset(30, 20));
      expect(editor.currentPointerKind, PointerDeviceKind.touch);
      expect(editor.lastSeenPointerCount, 2);
      await touch.up();
      await pen.up();
    }, platform: TargetPlatform.linux);
  });
}

void _platformTestWidgets(
  String description,
  WidgetTesterCallback callback, {
  TargetPlatform platform = TargetPlatform.android,
}) {
  testWidgets(description, (tester) async {
    await callback(tester);
    // Flush the existing HUD hook so it registers disposal of its hide timer.
    await tester.pump();
  }, variant: TargetPlatformVariant.only(platform));
}

extension on WidgetTester {
  Future<EditorState> _pumpEditor() async {
    await pumpWidget(MaterialApp(home: Editor(path: '/stylus-test')));
    return state<EditorState>(find.byType(Editor));
  }

  /// Similar to [timedDragFrom] but with support for [PointerDeviceKind].
  // TODO(adil192): Submit PRs to Flutter:
  //                - Add [PointerDeviceKind] to [timedDragFrom]
  //                - Add [buttons] to [TestPointer.hover]
  Future<void> _stylusDrag(
    EditorState editorState,
    bool withHover, {
    PointerDeviceKind kind = .stylus,
    int buttons = kPrimaryButton,
  }) async {
    final center = getCenter(find.byType(Editor));
    final gesture = await createGesture(kind: kind, buttons: buttons);

    if (withHover) {
      await gesture.moveTo(center);
      if (buttons == kSecondaryButton) {
        // Right now, [TestPointer.hover] doesn't pass through [buttons],
        // so fake it until that gets fixed in Flutter.
        editorState.onStylusButtonChanged(true);
      }
    }

    await gesture.down(center);
    for (var i = 0; i < 10; ++i) {
      await gesture.moveBy(
        Offset(i / 2, i / 2),
        timeStamp: Duration(seconds: i),
      );
    }
    await gesture.up(timeStamp: const Duration(seconds: 10));
  }
}
