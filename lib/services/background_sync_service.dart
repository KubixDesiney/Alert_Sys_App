// Background synchronization service for ensuring AI assignments
// and logs are properly synced when app wakes from sleep or comes online
//
// Handles:
// - App lifecycle transitions (to foreground)
// - Network reconnection
// - Periodic background sync
// - Offline queue management

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'ai_assignment_service.dart';

class BackgroundSyncService {
  BackgroundSyncService._();
  static final BackgroundSyncService instance = BackgroundSyncService._();

  final DatabaseReference _db = FirebaseDatabase.instance.ref();
  
  StreamSubscription<DatabaseEvent>? _connectionSubscription;
  Timer? _periodicSyncTimer;
  bool _isConnected = false;

  bool get isConnected => _isConnected;

  /// Initialize background sync monitoring
  void initialize() {
    // Monitor connection state to detect when we come back online
    _monitorConnectionState();
    
    // Set up periodic background sync every 5 minutes
    _startPeriodicSync();
  }

  /// Monitor Firebase connection state
  void _monitorConnectionState() {
    _connectionSubscription = _db.child('.info/connected').onValue.listen(
      (event) {
        final isConnected = event.snapshot.value as bool? ?? false;
        
        if (isConnected && !_isConnected) {
          // Connection established - sync immediately
          if (kDebugMode) {
            print('[BackgroundSync] Connected to Firebase - syncing AI history');
          }
          _performSync();
        } else if (!isConnected && _isConnected) {
          // Connection lost
          if (kDebugMode) {
            print('[BackgroundSync] Disconnected from Firebase');
          }
        }
        
        _isConnected = isConnected;
      },
      onError: (e) {
        if (kDebugMode) print('[BackgroundSync] Connection monitoring error: $e');
      },
    );
  }

  /// Set up periodic background sync
  void _startPeriodicSync() {
    // Cancel existing timer if any
    _periodicSyncTimer?.cancel();
    
    // Sync every 5 minutes for offline actions
    _periodicSyncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) {
        if (_isConnected) {
          if (kDebugMode) print('[BackgroundSync] Periodic sync triggered');
          _performSync();
        }
      },
    );
  }

  /// Perform a full sync of AI history and assignments
  Future<void> _performSync() async {
    try {
      // Sync recent AI assignments that may have happened while asleep
      await AIAssignmentService.instance.syncRecentAIHistory();
      
      if (kDebugMode) {
        print('[BackgroundSync] Sync completed successfully');
      }
    } catch (e) {
      if (kDebugMode) print('[BackgroundSync] Sync error: $e');
    }
  }

  /// Force an immediate sync (useful when app comes to foreground)
  Future<void> forceSyncNow() async {
    if (kDebugMode) print('[BackgroundSync] Forcing immediate sync');
    await _performSync();
  }

  /// Clean up resources
  void dispose() {
    _connectionSubscription?.cancel();
    _periodicSyncTimer?.cancel();
  }
}
