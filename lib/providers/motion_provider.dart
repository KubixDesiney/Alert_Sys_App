import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide "reduce motion" preference.
///
/// Decorative motion — the SuperAdmin neural-mesh background, pulsing status
/// dots, hover lifts and automatic transitions — is a vestibular-accessibility
/// concern (WCAG 2.3.3 Animation from Interactions). This provider persists an
/// explicit in-app toggle; [reduceMotionOf] also honours the operating system's
/// "reduce animations" accessibility flag, so a user who has set it at the OS
/// level gets the calm experience with no in-app action.
class MotionProvider extends ChangeNotifier {
  static const _key = 'reduceMotion';
  bool _reduceMotion = false;

  bool get reduceMotion => _reduceMotion;

  MotionProvider() {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _reduceMotion = prefs.getBool(_key) ?? false;
      notifyListeners();
    } catch (_) {
      // Preference is best-effort; default to full motion.
    }
  }

  Future<void> setReduceMotion(bool value) async {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {
      // Non-fatal; the in-memory value still drives the UI this session.
    }
  }

  Future<void> toggle() => setReduceMotion(!_reduceMotion);
}

/// Resolves the effective "reduce motion" state for [context]: true when either
/// the in-app [MotionProvider] toggle is on **or** the OS-level
/// `MediaQuery.disableAnimations` accessibility flag is set. Safe in tests and
/// provider-less widget trees (falls back to the OS flag, then to `false`).
bool reduceMotionOf(BuildContext context) {
  final os = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  bool pref = false;
  try {
    pref = Provider.of<MotionProvider>(context).reduceMotion;
  } catch (_) {
    // No provider in this subtree (e.g. widget test) — OS flag still applies.
  }
  return os || pref;
}
