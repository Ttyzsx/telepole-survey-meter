import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

import '../models/reading.dart';

/// สั่นและส่งเสียงเตือนตามระดับความรุนแรง
/// ออกแบบให้ "idempotent": เรียก update() ทุกวินาทีได้โดยไม่ทำให้เสียงซ้อนกัน
class AlarmService {
  final AudioPlayer _player = AudioPlayer();
  Timer? _pulseTimer;
  HazardLevel _current = HazardLevel.normal;
  bool _muted = false;
  bool _hasVibrator = false;
  bool _initialized = false;

  bool get isMuted => _muted;
  HazardLevel get level => _current;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _hasVibrator = await Vibration.hasVibrator() ?? false;
    await _player.setReleaseMode(ReleaseMode.stop);
  }

  set muted(bool value) {
    _muted = value;
    if (value) _stopPulse();
    else if (_current != HazardLevel.normal) _startPulse(_current);
  }

  /// เรียกทุกครั้งที่ได้ค่าใหม่ — เริ่ม/หยุดเสียงเฉพาะตอนที่ระดับ "เปลี่ยน"
  void update(HazardLevel level) {
    if (level == _current) return;
    _current = level;
    _stopPulse();
    if (level == HazardLevel.normal || _muted) return;
    _startPulse(level);
  }

  void _startPulse(HazardLevel level) {
    final interval = level == HazardLevel.alarm
        ? const Duration(milliseconds: 700)
        : const Duration(milliseconds: 2000);
    _fire(level);
    _pulseTimer = Timer.periodic(interval, (_) => _fire(level));
  }

  void _fire(HazardLevel level) {
    if (_muted) return;
    if (_hasVibrator) {
      if (level == HazardLevel.alarm) {
        Vibration.vibrate(pattern: const [0, 250, 120, 250], intensities: const [0, 255, 0, 255]);
      } else {
        Vibration.vibrate(duration: 120);
      }
    }
    // ถ้าไม่มีไฟล์เสียงใน assets ให้เงียบไปเฉย ๆ แทนที่จะโยน exception ขึ้น UI
    _player
        .play(AssetSource('alarm.wav'), volume: level == HazardLevel.alarm ? 1.0 : 0.5)
        .catchError((_) {});
  }

  void _stopPulse() {
    _pulseTimer?.cancel();
    _pulseTimer = null;
    _player.stop().catchError((_) {});
    if (_hasVibrator) Vibration.cancel();
  }

  void dispose() {
    _stopPulse();
    _player.dispose();
  }
}
