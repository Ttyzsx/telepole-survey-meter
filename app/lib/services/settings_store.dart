import 'package:shared_preferences/shared_preferences.dart';

import '../models/reading.dart';

/// ค่าที่ผู้ใช้ตั้งเองและต้องอยู่รอดข้ามการเปิด-ปิดแอป
class StoredSettings {
  final MeterCalibration calibration;
  final Thresholds thresholds;

  const StoredSettings({required this.calibration, required this.thresholds});
}

/// เก็บค่าสอบเทียบและเกณฑ์เตือนลงเครื่อง
///
/// ค่าสอบเทียบเป็นตัวที่สำคัญที่สุด เพราะกว่าจะได้มาต้องเอาหัววัดไปวางข้าง
/// เครื่องมาตรฐานแล้วจดค่า ถ้าหายไปตอนปิดแอป ครั้งต่อไปจะกลับไปใช้ค่า
/// datasheet เงียบ ๆ โดยไม่มีอะไรเตือน แล้วตัวเลขที่ลงรายงานจะผิดทั้งชุด
///
/// อ่านค่าไม่ได้หรือค่าที่เก็บไว้เพี้ยน ให้ถอยไปใช้ค่าเริ่มต้นเสมอ
/// ดีกว่าปล่อยให้แอปเปิดไม่ขึ้นเพราะ preferences เสีย
class SettingsStore {
  static const _keySensitivity = 'cpm_per_usvh';
  static const _keyElevated = 'threshold_elevated_usvh';
  static const _keyAlarm = 'threshold_alarm_usvh';

  /// ขอบเขตที่ยอมรับได้ของค่า sensitivity — กันค่าเพี้ยนจากการพิมพ์ผิด
  /// หลอด GM ที่ใช้งานจริงอยู่ในช่วงนี้ทั้งหมด (LND 712 = 108, J305 = 153.8)
  static const double _minSensitivity = 1.0;
  static const double _maxSensitivity = 100000.0;

  Future<StoredSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return StoredSettings(
        calibration: _readCalibration(prefs),
        thresholds: _readThresholds(prefs),
      );
    } catch (_) {
      // preferences ใช้ไม่ได้ (สิทธิ์ถูกปฏิเสธ / ข้อมูลเสีย) — เปิดแอปต่อด้วยค่าเริ่มต้น
      return const StoredSettings(
        calibration: MeterCalibration(),
        thresholds: Thresholds(),
      );
    }
  }

  Future<void> save({
    required MeterCalibration calibration,
    required Thresholds thresholds,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keySensitivity, calibration.cpmPerUSvh);
      await prefs.setDouble(_keyElevated, thresholds.elevated);
      await prefs.setDouble(_keyAlarm, thresholds.alarm);
    } catch (_) {
      // เซฟไม่ได้ก็ไม่ควรทำให้แอปล้ม ค่าที่ใส่ยังใช้ได้จนกว่าจะปิดแอป
    }
  }

  MeterCalibration _readCalibration(SharedPreferences prefs) {
    final stored = prefs.getDouble(_keySensitivity);
    if (stored == null ||
        stored.isNaN ||
        stored < _minSensitivity ||
        stored > _maxSensitivity) {
      return const MeterCalibration();
    }
    return MeterCalibration(cpmPerUSvh: stored);
  }

  Thresholds _readThresholds(SharedPreferences prefs) {
    const fallback = Thresholds();
    final elevated = prefs.getDouble(_keyElevated);
    final alarm = prefs.getDouble(_keyAlarm);
    if (elevated == null || alarm == null) return fallback;
    if (elevated.isNaN || alarm.isNaN || elevated <= 0 || alarm <= 0) {
      return fallback;
    }
    // เกณฑ์เตือนภัยต้องสูงกว่าเกณฑ์เฝ้าระวังเสมอ ไม่งั้นระดับความรุนแรงจะสลับกัน
    if (alarm < elevated) return fallback;
    return Thresholds(elevated: elevated, alarm: alarm);
  }
}
