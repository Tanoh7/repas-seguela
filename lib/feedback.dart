import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibration/vibration.dart';

/// Retours sonores et vibrations (réglables dans Réglages).
class Fx {
  static bool sound = true;
  static bool vibrate = true;
  static bool _hasVibrator = false;
  static final Map<String, AudioPlayer> _players = {};

  static Future<void> init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      sound = sp.getBool('fx_sound') ?? true;
      vibrate = sp.getBool('fx_vibrate') ?? true;
    } catch (_) {}
    try {
      _hasVibrator = await Vibration.hasVibrator();
    } catch (_) {
      _hasVibrator = false;
    }
    for (final n in const ['ok', 'success', 'error', 'tick']) {
      try {
        final p = AudioPlayer(playerId: 'fx_$n');
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setPlayerMode(PlayerMode.lowLatency);
        _players[n] = p;
      } catch (_) {}
    }
  }

  static Future<void> setSound(bool v) async {
    sound = v;
    try {
      (await SharedPreferences.getInstance()).setBool('fx_sound', v);
    } catch (_) {}
  }

  static Future<void> setVibrate(bool v) async {
    vibrate = v;
    try {
      (await SharedPreferences.getInstance()).setBool('fx_vibrate', v);
    } catch (_) {}
  }

  static void _play(String n, {double volume = 1.0}) {
    if (!sound) return;
    final p = _players[n];
    if (p == null) return;
    p.stop().then((_) => p.play(AssetSource('sounds/$n.wav'), volume: volume)).catchError((_) {});
  }

  static void _buzz(int ms, int amplitude, Future<void> Function() fallback) {
    if (!vibrate) return;
    if (_hasVibrator) {
      Vibration.vibrate(duration: ms, amplitude: amplitude).catchError((_) => fallback());
    } else {
      fallback();
    }
  }

  /// Toucher d'un bouton − / + : petit clic.
  static void tick() {
    _buzz(12, 40, HapticFeedback.selectionClick);
    _play('tick', volume: 0.6);
  }

  /// Département validé : « ding » + vibration légère.
  static void ok() {
    _buzz(35, 90, HapticFeedback.lightImpact);
    _play('ok');
  }

  /// Commande envoyée / confirmée.
  static void success() {
    _buzz(60, 140, HapticFeedback.mediumImpact);
    Timer(const Duration(milliseconds: 160), () => _buzz(40, 90, HapticFeedback.lightImpact));
    _play('success');
  }

  /// Action impossible.
  static void error() {
    _buzz(90, 200, HapticFeedback.heavyImpact);
    Timer(const Duration(milliseconds: 180), () => _buzz(90, 200, HapticFeedback.heavyImpact));
    _play('error');
  }
}
