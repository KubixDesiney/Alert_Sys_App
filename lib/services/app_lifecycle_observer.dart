// App lifecycle observer for handling app state transitions
// Ensures AI history is synced when app comes to foreground

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'background_sync_service.dart';

class AppLifecycleObserver extends WidgetsBindingObserver {
  AppLifecycleObserver() : _isPaused = false;
  
  bool _isPaused = false;
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_isPaused) {
          // App came back to foreground after being paused
          if (kDebugMode) {
            print('[AppLifecycle] App resumed - triggering AI sync');
          }
          // Force sync AI history when coming back from background
          BackgroundSyncService.instance.forceSyncNow();
        }
        _isPaused = false;
        break;
        
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
          case AppLifecycleState.inactive:
        _isPaused = true;
        if (kDebugMode) {
          print('[AppLifecycle] App paused/hidden - maintaining background listeners');
        }
        break;
    }
    super.didChangeAppLifecycleState(state);
  }
}
