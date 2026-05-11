import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationTrackingService {
  LocationTrackingService._({DatabaseReference? database})
      : _db = database ?? FirebaseDatabase.instance.ref();

  static final LocationTrackingService instance = LocationTrackingService._();

  final DatabaseReference _db;
  Timer? _timer;
  StreamSubscription<DatabaseEvent>? _roleSubscription;
  String? _uid;
  bool _writeInFlight = false;

  static const Duration interval = Duration(seconds: 60);

  Future<void> updateForRole({
    required String uid,
    required String? role,
  }) async {
    if (role == 'supervisor') {
      await start(uid);
    } else {
      await stop();
    }
  }

  Future<void> start(String uid) async {
    if (_uid == uid && _timer?.isActive == true) return;
    await stop();
    _uid = uid;
    _roleSubscription = _db.child('users/$uid/role').onValue.listen((event) {
      final role = event.snapshot.value?.toString();
      if (role != null && role != 'supervisor') {
        unawaited(stop());
      }
    });
    await _writeCurrentLocation();
    _timer = Timer.periodic(interval, (_) {
      unawaited(_writeCurrentLocation());
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _roleSubscription?.cancel();
    _roleSubscription = null;
    _uid = null;
    _writeInFlight = false;
  }

  Future<bool> _ensurePermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> _writeCurrentLocation() async {
    final uid = _uid;
    if (uid == null || _writeInFlight) return;
    _writeInFlight = true;
    try {
      if (!await _ensurePermission()) return;
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await _db.child('users/$uid/currentLocation').set({
        'lat': position.latitude,
        'lng': position.longitude,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Location tracking skipped: $e');
    } finally {
      _writeInFlight = false;
    }
  }
}
