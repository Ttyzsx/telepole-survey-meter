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

  /// จำนวนพัลส์ดิบของวินาทีล่าสุด ไม่ผ่านการเฉลี่ย — ตอบสนองทันที
  /// เป็น null ถ้าเชื่อมกับ firmware รุ่นเก่าที่ยังส่งมาแค่ 3 ช่อง
  final int? cps;

  final DateTime timestamp;

  const Reading({
    required this.cpm,
    required this.deviceDoseRate,
    required this.deviceAccumulated,
    required this.timestamp,
    this.cps,
  });

  /// แปลงหนึ่งบรรทัด CSV "CPM,uSv_h,Accumulated_uSv[,CPS]" เป็น [Reading].
  /// ช่อง CPS เพิ่มมาทีหลัง จึงถือเป็นช่องเสริม — firmware รุ่นเก่าที่ส่งมา 3 ช่องยังใช้ได้
  /// คืน null ถ้าบรรทัดนั้นเป็น comment (#...) หรือรูปแบบไม่ถูกต้อง
  /// เพื่อไม่ให้ข้อมูลขยะทำให้ stream ล้ม
  static Reading? tryParse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return null;

    if (trimmed.contains('=')) return _tryParseKeyValue(trimmed);

    final parts = trimmed.split(',');
    if (parts.length < 3) return null;

    final cpm = double.tryParse(parts[0].trim());
    final rate = double.tryParse(parts[1].trim());
    final dose = double.tryParse(parts[2].trim());
    if (cpm == null || rate == null || dose == null) return null;
    if (cpm < 0 || rate < 0 || dose < 0) return null;

    final cps = parts.length >= 4 ? int.tryParse(parts[3].trim()) : null;

    return Reading(
      cpm: cpm,
      deviceDoseRate: rate,
      deviceAccumulated: dose,
      cps: cps != null && cps >= 0 ? cps : null,
      timestamp: DateTime.now(),
    );
  }

  /// รูปแบบ "cpm=123;uSv/h=1.230" ของสเก็ตช์ gm_final (ส่งทุก 10 วินาที)
  /// ต้องมี cpm เสมอ ส่วน uSv/h เป็นช่องเสริม และไม่มีค่าสะสมหรือ CPS มาด้วย
  /// หมายเหตุ: uSv/h ของบอร์ดหัก background ไปแล้ว แต่ cpm ที่ส่งมาเป็นค่าดิบ
  static Reading? _tryParseKeyValue(String line) {
    final fields = <String, String>{};
    for (final pair in line.split(';')) {
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      fields[pair.substring(0, eq).trim().toLowerCase()] =
          pair.substring(eq + 1).trim();
    }

    final cpm = double.tryParse(fields['cpm'] ?? '');
    if (cpm == null || cpm < 0) return null;
    final rate = double.tryParse(fields['usv/h'] ?? '');

    return Reading(
      cpm: cpm,
      deviceDoseRate: rate != null && rate >= 0 ? rate : 0,
      deviceAccumulated: 0,
      timestamp: DateTime.now(),
    );
  }
}

/// ค่าสอบเทียบของหลอด GM: กี่ CPM ต่อ 1 uSv/h
///
/// ค่านี้ผู้ผลิตหลอดวัดมาให้ที่พลังงานอ้างอิงจุดเดียว (Cs-137 662 keV หรือ Co-60)
/// เพราะหลอด GM ตอบสนองต่างกันตามพลังงานโฟตอน จึงต้องมีจุดอ้างอิงจุดเดียว
/// ค่า uSv/h ที่แสดงจึงเป็น "ค่าเทียบเท่า" ไม่ใช่ค่าสัมบูรณ์ — ส่วน CPM คือค่าจริง
class MeterCalibration {
  final double cpmPerUSvh;

  /// ค่าตั้งต้น = LND 712 ซึ่งเป็นหลอดที่เครื่องนี้ใช้จริง
  const MeterCalibration({this.cpmPerUSvh = defaultCpmPerUSvh});

  /// LND 712: datasheet ระบุ 18 CPS ต่อ 1 mR/h (Co-60)
  /// 18 CPS = 1080 CPM, 1 mR/h ~ 10 uSv/h  ->  108 CPM ต่อ 1 uSv/h
  static const double defaultCpmPerUSvh = 108.0;

  /// ค่าที่พบบ่อยของหลอดยอดนิยม (จาก datasheet, อ้างอิง Cs-137)
  static const Map<String, double> presets = {
    'LND 712': defaultCpmPerUSvh,
    'J305 / M4011': 153.8,
    'SBM-20': 150.5,
    'STS-5': 148.0,
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
