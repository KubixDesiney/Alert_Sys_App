import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// App-wide connectivity signal. Built on connectivity_plus so it works on
/// every platform (web included). Exposes a [ChangeNotifier] so widgets can
/// `context.watch` it without juggling stream subscriptions, plus a raw
/// [stream] for non-widget consumers.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _isOnline = true;
  bool _initialized = false;

  bool get isOnline => _isOnline;
  bool get isOffline => !_isOnline;

  Stream<bool> get stream => _controller.stream;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final initial = await _connectivity.checkConnectivity();
      _apply(initial);
    } catch (e) {
      debugPrint('ConnectivityService: initial check failed: $e');
    }
    _sub = _connectivity.onConnectivityChanged.listen(
      _apply,
      onError: (Object e) =>
          debugPrint('ConnectivityService stream error: $e'),
    );
  }

  void _apply(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (online != _isOnline) {
      _isOnline = online;
      _controller.add(online);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.close();
    super.dispose();
  }
}
