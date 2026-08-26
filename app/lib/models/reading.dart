/// หนึ่งเฟรมข้อมูลที่ได้จากเครื่องวัด
///
/// [cpm] คือค่าดิบที่หลอด GM วัดได้จริง ไม่มีสมมติฐานใด ๆ แฝง
/// ส่วน [deviceDoseRate] / [deviceAccumulated] เป็นค่าที่ firmware คำนวณมาให้
/// ซึ่งขึ้นกับค่า sensitivity ที่ hardcode ไว้ในบอร์ด — แอปเก็บไว้เพื่ออ้างอิง
/// แต่จะ "คำนวณใหม่เอง" จาก [cpm] เพื่อให้ผู้ใช้ปรับค่า sensitivity ได้โดยไม่ต้อง flash ใหม่
class Reading {
  final double cpm;
  final double deviceDoseRate; // uSv/h ตามที่ firmware คำนวณ
  final double deviceAccumulated; // uSv ตามที่ firmware สะสม
  final DateTime timestamp;

  const Reading({
    required this.cpm,
    required this.deviceDoseRate,
    required this.deviceAccumulated,
    required this.timestamp,
  });

  /// แปลงหนึ่งบรรทัด CSV "CPM,uSv_h,Accumulated_uSv" เป็น [Reading].
  /// คืน null ถ้าบรรทัดนั้นเป็น comment (#...) หรือรูปแบบไม่ถูกต้อง
  /// เพื่อไม่ให้ข้อมูลขยะทำให้ stream ล้ม
  static Reading? tryParse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;

    final parts = trimmed.split(',');
    if (parts.length < 3) return null;

    final cpm = double.tryParse(parts[0].trim());
    final rate = double.tryParse(parts[1].trim());
    final dose = double.tryParse(parts[2].trim());
    if (cpm == null || rate == null || dose == null) return null;
    if (cpm < 0 || rate < 0 || dose < 0) return null;

    return Reading(
      cpm: cpm,
      deviceDoseRate: rate,
      deviceAccumulated: dose,
      timestamp: DateTime.now(),
    );
  }
}

/// ค่าสอบเทียบของหลอด GM: กี่ CPM ต่อ 1 uSv/h
///
/// ค่านี้ผู้ผลิตหลอดวัดมาให้ที่พลังงานอ้างอิง Cs-137 (662 keV) เพราะหลอด GM
/// ตอบสนองต่างกันตามพลังงานโฟตอน จึงต้องมีจุดอ้างอิงจุดเดียว
/// ค่า uSv/h ที่แสดงจึงเป็น "ค่าเทียบเท่า" ไม่ใช่ค่าสัมบูรณ์ — ส่วน CPM คือค่าจริง
class MeterCalibration {
  final double cpmPerUSvh;

  const MeterCalibration({this.cpmPerUSvh = 153.8});

  /// ค่าที่พบบ่อยของหลอดยอดนิยม (จาก datasheet, อ้างอิง Cs-137)
  static const Map<String, double> presets = {
    'J305 / M4011': 153.8,
    'SBM-20': 150.5,
    'STS-5': 148.0,
    'LND712': 108.0,
  };

  double doseRateFor(double cpm) => cpmPerUSvh <= 0 ? 0 : cpm / cpmPerUSvh;

  double cpmFor(double doseRate) => doseRate * cpmPerUSvh;
}

/// ระดับความรุนแรงที่ใช้ขับสี UI และเสียงเตือน
enum HazardLevel { normal, elevated, alarm }

/// เกณฑ์เตือนเก็บเป็นหน่วย uSv/h เพราะเป็นหน่วยที่ใช้อ้างอิงกันในงานความปลอดภัย
/// แต่หน้าจอจะแสดงค่า CPM ที่เทียบเท่าให้ด้วยเสมอ
class Thresholds {
  final double elevated; // uSv/h
  final double alarm; // uSv/h

  const Thresholds({this.elevated = 0.5, this.alarm = 2.5});

  HazardLevel levelFor(double doseRate) {
    if (doseRate >= alarm) return HazardLevel.alarm;
    if (doseRate >= elevated) return HazardLevel.elevated;
    return HazardLevel.normal;
  }

  Thresholds copyWith({double? elevated, double? alarm}) => Thresholds(
        elevated: elevated ?? this.elevated,
        alarm: alarm ?? this.alarm,
      );
}
