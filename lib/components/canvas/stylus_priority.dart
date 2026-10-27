import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Arbitrates pen and touch input for one mounted editor, including its popups.
///
/// Touches rejected during pen use remain rejected until lifted. A real hover
/// renews a bounded lease because some Android devices omit hover-exit events.
/// This cannot identify a palm before the OS reports any pen contact or hover.
class StylusPriorityController extends ChangeNotifier
    with WidgetsBindingObserver {
  new({this._enabled = false, this.onTakeover}) {
    GestureBinding.instance.pointerRouter.addGlobalRoute(observe);
    WidgetsBinding.instance.addObserver(this);
  }

  static const cooldown = Duration(milliseconds: 400);

  /// Invoked after existing touch recognizers have been canceled.
  VoidCallback? onTakeover;

  bool _enabled;
  bool get enabled => _enabled;
  set enabled(bool value) {
    if (_enabled == value) return;
    reset();
    _enabled = value;
    notifyListeners();
  }

  final Map<int, PointerEvent> _touches = {};
  final Map<int, int> _contacts = {};
  final Set<int> _blocked = {};
  Timer? _lease;
  var _recentPen = false;
  var _isCancellingTouches = false;

  /// True while synthetic cancellation is being delivered to touch recognizers.
  bool get isCancellingTouches => _isCancellingTouches;

  /// Whether new touch sequences must yield to pen contact, hover or cooldown.
  bool get touchSuppressed => enabled && (_contacts.isNotEmpty || _recentPen);

  bool isBlocked(int pointer) => enabled && _blocked.contains(pointer);

  /// Used by raw input listeners before updating pressure or tool state.
  bool shouldReject(PointerEvent event) =>
      enabled &&
      // GestureBinding.cancelPointer synthesizes a cancel with the default
      // touch kind, even for a pen. Its tracked identity must take precedence.
      !_contacts.containsKey(event.pointer) &&
      (isBlocked(event.pointer) ||
          (event.kind == PointerDeviceKind.touch && touchSuppressed));

  static bool _isPen(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus;

  void _renewLease() {
    _recentPen = true;
    _lease?.cancel();
    _lease = Timer(cooldown, () {
      _recentPen = false;
      _lease = null;
      notifyListeners();
    });
  }

  void _takeover() {
    _isCancellingTouches = true;
    try {
      // Stop an already running fling even if no finger remains in contact.
      notifyListeners();
      for (final event in _touches.values.toList()) {
        if (!_blocked.add(event.pointer)) continue;
        // Route synchronously: the old scale membership must be gone before
        // the arriving pen is admitted. Keep the physical hit-test sequence
        // intact so its eventual up can release this pointer's quarantine.
        GestureBinding.instance.pointerRouter.route(
          PointerCancelEvent(
            pointer: event.pointer,
            device: event.device,
            kind: event.kind,
            position: event.position,
            timeStamp: event.timeStamp,
          ),
        );
      }
      onTakeover?.call();
    } finally {
      _isCancellingTouches = false;
    }
  }

  /// Observes input before scale admission and globally for toolbar overlays.
  /// Repeated observations of the same event are harmless.
  void observe(PointerEvent event) {
    if (!enabled || _isCancellingTouches) return;
    if (_isPen(event) || _contacts.containsKey(event.pointer)) {
      if (event is PointerDownEvent) {
        final newContact = !_contacts.containsKey(event.pointer);
        _contacts[event.pointer] = event.device;
        _renewLease();
        if (newContact) _takeover();
      } else if (event is PointerHoverEvent && !event.synthesized) {
        final wasSuppressed = touchSuppressed;
        _renewLease();
        if (!wasSuppressed) _takeover();
      } else if (event is PointerUpEvent || event is PointerCancelEvent) {
        _contacts.remove(event.pointer);
        _renewLease();
      } else if (event is PointerRemovedEvent) {
        _contacts.removeWhere((pointer, device) => device == event.device);
        _renewLease();
      }
      return;
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _touches.remove(event.pointer);
      _blocked.remove(event.pointer);
      return;
    }
    if (event.kind != PointerDeviceKind.touch) return;
    if (event is PointerDownEvent) {
      _touches[event.pointer] = event;
      if (touchSuppressed && _blocked.add(event.pointer)) {
        // Global routes run before the down arena closes. This also protects
        // popup controls outside the editor's render subtree.
        GestureBinding.instance.gestureArena
            .add(event.pointer, const _RejectedTouch())
            .resolve(GestureDisposition.accepted);
      }
    } else if (event is PointerMoveEvent &&
        _touches.containsKey(event.pointer)) {
      _touches[event.pointer] = event;
    }
  }

  /// Drops transient pen state when the editor is disabled or loses focus.
  void reset() {
    _lease?.cancel();
    _lease = null;
    _recentPen = false;
    // A platform may omit the final pen cancel when focus is lost. End its
    // binding sequence too, so fresh touches cannot join a stale scale gesture.
    for (final pointer in _contacts.keys) {
      GestureBinding.instance.cancelPointer(pointer);
    }
    _contacts.clear();
    if (enabled) _takeover();
    _touches.clear();
    _blocked.clear();
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) reset();
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(observe);
    WidgetsBinding.instance.removeObserver(this);
    _lease?.cancel();
    super.dispose();
  }
}

class _RejectedTouch implements GestureArenaMember {
  const new();

  @override
  void acceptGesture(int pointer) {}

  @override
  void rejectGesture(int pointer) {}
}

/// Protects controls without blocking pen, keyboard or accessibility actions.
class StylusPriorityRegion extends StatelessWidget {
  const new({super.key, required this.controller, required this.child});

  final StylusPriorityController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.translucent,
    gestures: {
      _PriorityGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<_PriorityGestureRecognizer>(
            () => _PriorityGestureRecognizer(),
            (recognizer) => recognizer.controller = controller,
          ),
    },
    child: child,
  );
}

class _PriorityGestureRecognizer extends OneSequenceGestureRecognizer {
  late StylusPriorityController controller;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    controller.observe(event);
    if (!controller.shouldReject(event)) return;
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) =>
      stopTrackingIfPointerNoLongerDown(event);

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'stylus priority';
}

/// Keeps rejected touch pointers out of scale counts and focal points entirely.
class StylusPriorityScaleGestureRecognizer extends ScaleGestureRecognizer {
  new({this.controller, super.debugOwner, super.supportedDevices});

  StylusPriorityController? controller;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    controller?.observe(event);
    if (controller?.shouldReject(event) ?? false) return;
    super.addAllowedPointer(event);
  }
}
