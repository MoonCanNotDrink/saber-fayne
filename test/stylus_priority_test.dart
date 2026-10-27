import 'dart:ui' show SemanticsAction;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saber/components/canvas/interactive_canvas.dart';
import 'package:saber/components/canvas/stylus_priority.dart';

void main() {
  testWidgets('pen-first excludes multiple palms from scale recognition', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    final pen = await tester.startGesture(harness.canvas, kind: .stylus);
    await pen.moveBy(const Offset(40, 0));
    final firstPalm = await tester.startGesture(harness.canvas);
    final secondPalm = await tester.startGesture(
      harness.canvas + const Offset(60, 0),
    );
    await firstPalm.moveBy(const Offset(100, 100));
    await secondPalm.moveBy(const Offset(-100, -100));
    await pen.moveBy(const Offset(20, 10));

    expect(harness.updates, isNotEmpty);
    expect(
      harness.updates.every((details) => details.pointerCount == 1),
      isTrue,
    );
    expect(
      harness.updates.last.focalPoint,
      harness.canvas + const Offset(60, 10),
    );
    await firstPalm.up();
    await secondPalm.up();
    await pen.up();
    await harness.close();
  });

  testWidgets('palm-first gesture is cancelled before the pen is admitted', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    final firstPalm = await tester.startGesture(harness.canvas);
    final secondPalm = await tester.startGesture(
      harness.canvas + const Offset(60, 0),
    );
    await firstPalm.moveBy(const Offset(0, -40));
    await secondPalm.moveBy(const Offset(40, -40));
    expect(harness.updates.any((details) => details.pointerCount == 2), isTrue);

    final pen = await tester.startGesture(harness.canvas, kind: .stylus);
    harness.updates.clear();
    await pen.moveBy(const Offset(40, 10));
    await pen.moveBy(const Offset(20, 10));
    await firstPalm.moveBy(const Offset(100, 100));
    await secondPalm.moveBy(const Offset(100, 100));
    expect(harness.updates, isNotEmpty);
    expect(
      harness.updates.every((details) => details.pointerCount == 1),
      isTrue,
    );
    expect(
      harness.updates.last.focalPoint,
      harness.canvas + const Offset(60, 20),
    );

    await firstPalm.cancel();
    await secondPalm.up();
    await pen.up();
    await harness.close();
  });

  testWidgets('pen takeover cancels a pending toolbar finger tap', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    final finger = await tester.startGesture(harness.toolbar);
    final pen = await tester.startGesture(harness.canvas, kind: .stylus);
    // No pump between pen arrival and finger-up: cancellation must be immediate.
    await finger.up();
    expect(harness.taps, 0);
    await pen.up();
    await harness.close();
  });

  testWidgets('toolbar rejects fingers but accepts intentional pen taps', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    final pen = await tester.startGesture(harness.canvas, kind: .stylus);
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 0);
    await pen.up();
    await tester.tap(find.byKey(_toolbarKey), kind: .stylus);
    expect(harness.taps, 1);
    await harness.close();
  });

  testWidgets('finger navigation and toolbar taps recover after 400 ms', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    final pen = await tester.startGesture(harness.canvas, kind: .stylus);
    await pen.up();
    await tester.pump(const Duration(milliseconds: 399));
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 0);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 1);
    await tester.dragFrom(harness.canvas, const Offset(40, 0));
    expect(harness.updates.any((details) => details.pointerCount == 1), isTrue);
    final first = await tester.startGesture(harness.canvas);
    final second = await tester.startGesture(
      harness.canvas + const Offset(60, 0),
    );
    await first.moveBy(const Offset(-40, 0));
    await second.moveBy(const Offset(40, 0));
    expect(harness.updates.any((details) => details.pointerCount == 2), isTrue);
    await first.up();
    await second.up();
    await harness.close();
  });

  testWidgets('resting rejected palm never rejoins after cooldown', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    final pen = await tester.startGesture(harness.canvas, kind: .stylus);
    final palm = await tester.startGesture(harness.canvas);
    await pen.up();
    await tester.pump(const Duration(seconds: 1));
    harness.updates.clear();
    await palm.moveBy(const Offset(150, 150));
    expect(harness.updates, isEmpty);
    await palm.up();
    await tester.dragFrom(harness.canvas, const Offset(60, 0));
    expect(harness.updates, isNotEmpty);
    await harness.close();
  });

  testWidgets('genuine hover refreshes a bounded rejection lease', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    final pen = await tester.createGesture(kind: .stylus);
    await pen.addPointer(location: harness.canvas);
    await pen.moveTo(harness.canvas);
    await tester.pump(const Duration(milliseconds: 300));
    await pen.moveTo(harness.canvas + const Offset(5, 0));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 0);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 1);
    await pen.removePointer();
    await harness.close();
  });

  testWidgets('synthetic hover alone does not disable finger input', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    await tester.sendEventToBinding(
      PointerHoverEvent(
        kind: .stylus,
        position: harness.canvas,
        synthesized: true,
      ),
    );
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 1);
    await harness.close();
  });

  testWidgets('no-hover contact persists, cancel starts bounded cooldown', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    final pen = await tester.startGesture(harness.canvas, kind: .stylus);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 0);
    await pen.cancel();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 1);
    await harness.close();
  });

  testWidgets('inverted stylus hover and contact reject palms', (tester) async {
    final harness = await _Harness.pump(tester);
    final pen = await tester.createGesture(kind: .invertedStylus);
    await pen.addPointer(location: harness.canvas);
    await pen.moveTo(harness.canvas);
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 0);
    await pen.down(harness.canvas);
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 0);
    await pen.up();
    await pen.removePointer();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 1);
    await harness.close();
  });

  testWidgets('one pen ending does not clear another active pen pointer', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    final first = await tester.startGesture(harness.canvas, kind: .stylus);
    final second = await tester.startGesture(
      harness.canvas + const Offset(30, 0),
      kind: .invertedStylus,
    );
    await first.cancel();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 0);
    await second.up();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 1);
    await harness.close();
  });

  testWidgets('popup overlay finger taps are rejected, pen taps work', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    await tester.tap(find.byKey(_popupKey));
    await tester.pumpAndSettle();
    final popupItem = find.byKey(_popupItemKey);
    final pen = await tester.createGesture(kind: .stylus);
    await pen.addPointer(location: tester.getCenter(popupItem));
    await pen.moveTo(tester.getCenter(popupItem));
    await tester.tap(popupItem);
    expect(harness.popupTaps, 0);
    await tester.tap(popupItem, kind: .stylus);
    expect(harness.popupTaps, 1);
    await pen.removePointer();
    await harness.close();
  });

  testWidgets('feature off preserves mixed-pointer gestures and finger taps', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester, enabled: false);
    final pen = await tester.startGesture(harness.canvas, kind: .stylus);
    final finger = await tester.startGesture(
      harness.canvas + const Offset(50, 0),
    );
    await pen.moveBy(const Offset(-40, 0));
    await finger.moveBy(const Offset(40, 0));
    expect(harness.updates.any((details) => details.pointerCount == 2), isTrue);
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 1);
    await finger.up();
    await pen.up();
    await harness.close();
  });

  testWidgets('mouse input remains available during stylus contact', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    final pen = await tester.startGesture(harness.canvas, kind: .stylus);
    await tester.tap(find.byKey(_toolbarKey), kind: .mouse);
    expect(harness.taps, 1);
    await pen.up();
    await harness.close();
  });

  testWidgets('accessibility actions remain available during pen contact', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final harness = await _Harness.pump(tester);
    final pen = await tester.startGesture(harness.canvas, kind: .stylus);
    final button = tester.getSemantics(find.byKey(_toolbarKey));
    button.owner!.performAction(button.id, SemanticsAction.tap);
    expect(harness.taps, 1);
    await pen.up();
    handle.dispose();
    await harness.close();
  });

  testWidgets('background and resume clear stale stylus contact', (
    tester,
  ) async {
    final harness = await _Harness.pump(tester);
    final pen = await tester.startGesture(harness.canvas, kind: .stylus);
    await pen.moveBy(const Offset(40, 10));
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
    // The OS may omit a pen cancel while backgrounding. Flush our queued cancel
    // and verify scale membership recovers without manually releasing the pen.
    await tester.pump();
    harness.updates.clear();
    await tester.dragFrom(harness.canvas, const Offset(70, 20));
    expect(harness.updates, isNotEmpty);
    expect(
      harness.updates.every((details) => details.pointerCount == 1),
      isTrue,
    );
    await tester.tap(find.byKey(_toolbarKey));
    expect(harness.taps, 1);
    await harness.close();
  });

  testWidgets('genuine hover stops an existing canvas fling', (tester) async {
    final controller = StylusPriorityController(enabled: true);
    final transform = TransformationController();
    await tester.pumpWidget(
      MaterialApp(
        home: StylusPriorityRegion(
          controller: controller,
          child: InteractiveCanvasViewer(
            stylusPriority: controller,
            transformationController: transform,
            constrained: false,
            boundaryMargin: const EdgeInsets.all(2000),
            child: const SizedBox(width: 2000, height: 2000),
          ),
        ),
      ),
    );
    final center = tester.getCenter(find.byType(InteractiveCanvasViewer));
    await tester.flingFrom(center, const Offset(0, -200), 2000);
    await tester.pump();
    final released = transform.value.clone();
    await tester.pump(const Duration(milliseconds: 32));
    expect(
      transform.value,
      isNot(released),
      reason: 'The fling must be active.',
    );
    final pen = await tester.createGesture(kind: .stylus);
    await pen.addPointer(location: center);
    await pen.moveTo(center);
    final atHover = transform.value.clone();
    await tester.pump(const Duration(milliseconds: 100));
    expect(transform.value, atHover);
    await pen.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    transform.dispose();
  });
}

const _canvasKey = ValueKey('test canvas');
const _toolbarKey = ValueKey('test toolbar');
const _popupKey = ValueKey('open test popup');
const _popupItemKey = ValueKey('test popup item');

class _Harness {
  new(this.tester, {required bool enabled})
    : controller = StylusPriorityController(enabled: enabled);

  final WidgetTester tester;
  final StylusPriorityController controller;
  final updates = <ScaleUpdateDetails>[];
  var taps = 0;
  var popupTaps = 0;
  var _closed = false;

  Offset get canvas => tester.getCenter(find.byKey(_canvasKey));
  Offset get toolbar => tester.getCenter(find.byKey(_toolbarKey));

  static Future<_Harness> pump(
    WidgetTester tester, {
    bool enabled = true,
  }) async {
    final harness = _Harness(tester, enabled: enabled);
    addTearDown(() {
      if (!harness._closed) harness.controller.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: StylusPriorityRegion(
          controller: harness.controller,
          child: Scaffold(
            body: Column(
              children: [
                TextButton(
                  key: _toolbarKey,
                  onPressed: () => harness.taps++,
                  child: const Text('Tool'),
                ),
                Builder(
                  builder: (context) => TextButton(
                    key: _popupKey,
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => AlertDialog(
                        content: TextButton(
                          key: _popupItemKey,
                          onPressed: () => harness.popupTaps++,
                          child: const Text('Popup tool'),
                        ),
                      ),
                    ),
                    child: const Text('Open popup'),
                  ),
                ),
                Expanded(
                  child: RawGestureDetector(
                    key: _canvasKey,
                    behavior: HitTestBehavior.opaque,
                    gestures: {
                      StylusPriorityScaleGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            StylusPriorityScaleGestureRecognizer
                          >(
                            () => StylusPriorityScaleGestureRecognizer(
                              controller: harness.controller,
                            ),
                            (recognizer) {
                              recognizer.onStart = (_) {};
                              recognizer.onUpdate = harness.updates.add;
                              recognizer.onEnd = (_) {};
                            },
                          ),
                    },
                    child: const SizedBox.expand(
                      child: ColoredBox(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return harness;
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    _closed = true;
  }
}
