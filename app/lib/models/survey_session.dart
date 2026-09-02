import 'dart:io';

/// หนึ่งแถวข้อมูลที่บันทึกลงไฟล์ระหว่างการสำรวจ
///
/// เก็บทั้งค่าดิบ ([cpm], [cps]) และค่าที่คำนวณแล้ว ([doseRate], [accumulatedUSv])
/// เพราะค่าที่คำนวณขึ้นกับค่าสอบเทียบ "ณ ขณะบันทึก" ซึ่งอาจไม่ใช่ค่าที่ตั้งอยู่ตอนเปิดดูภายหลัง
/// การเก็บทั้งสองอย่างทำให้ไฟล์อ่านย้อนหลังได้โดยไม่ต้องเดาว่าตอนนั้นตั้งค่าอะไรไว้
class SurveySample {
  final DateTime timestamp;
  final double elapsedSeconds;
  final double cpm;
  final int? cps;
  final double doseRate; // uSv/h
  final double accumulatedUSv;

  const SurveySample({
    required this.timestamp,
    required this.elapsedSeconds,
    required this.cpm,
    required this.doseRate,
    required this.accumulatedUSv,
    this.cps,
  });

  String toCsvRow() => [
        timestamp.toIso8601String(),
        elapsedSeconds.toStringAsFixed(1),
        cpm.toStringAsFixed(1),
        cps?.toString() ?? '',
        doseRate.toStringAsFixed(4),
        accumulatedUSv.toStringAsFixed(5),
      ].join(',');

  /// คืน null ถ้าบรรทัดเสียหาย เพื่อให้ไฟล์ที่ถูกตัดกลางคัน (แบตหมด/แอปถูกฆ่า)
  /// ยังเปิดดูส่วนที่สมบูรณ์ได้ แทนที่จะเปิดไม่ได้ทั้งไฟล์
  static SurveySample? tryParse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('timestamp')) {
      return null;
    }

    final parts = trimmed.split(',');
    if (parts.length < 6) return null;

    final timestamp = DateTime.tryParse(parts[0]);
    final elapsed = double.tryParse(parts[1]);
    final cpm = double.tryParse(parts[2]);
    final doseRate = double.tryParse(parts[4]);
    final accumulated = double.tryParse(parts[5]);
    if (timestamp == null ||
        elapsed == null ||
        cpm == null ||
        doseRate == null ||
        accumulated == null) {
      return null;
    }

    return SurveySample(
      timestamp: timestamp,
      elapsedSeconds: elapsed,
      cpm: cpm,
      cps: int.tryParse(parts[3]),
      doseRate: doseRate,
      accumulatedUSv: accumulated,
    );
  }
}

/// การสำรวจหนึ่งครั้งที่บันทึกไว้ = ไฟล์ CSV หนึ่งไฟล์
class SurveySession {
  final String id; // ชื่อไฟล์ไม่รวมนามสกุล
  final String path;
  final DateTime startedAt;
  final double cpmPerUSvh; // ค่าสอบเทียบที่ใช้ตอนบันทึก
  final String? note;
  final List<SurveySample> samples;

  const SurveySession({
    required this.id,
    required this.path,
    required this.startedAt,
    required this.cpmPerUSvh,
    required this.samples,
    this.note,
  });

  static const String csvHeader =
      'timestamp,elapsed_s,cpm,cps,usv_h,accumulated_usv';

  /// หัวไฟล์เป็นบรรทัด comment (#) เพื่อให้ Excel/pandas ข้ามได้ง่าย
  /// และเก็บค่าสอบเทียบไว้ด้วย ไม่งั้นเปิดไฟล์ย้อนหลังแล้วตีความ uSv/h ไม่ได้
  static String headerFor({
    required DateTime startedAt,
    required double cpmPerUSvh,
    String? note,
  }) {
    final lines = [
      '# telepole-session v1',
      '# started_at=${startedAt.toIso8601String()}',
      '# cpm_per_usvh=${cpmPerUSvh.toStringAsFixed(2)}',
      if (note != null && note.trim().isNotEmpty) '# note=${note.trim()}',
      csvHeader,
    ];
    return '${lines.join('\n')}\n';
  }

  Duration get duration => samples.length < 2
      ? Duration.zero
      : Duration(milliseconds: (samples.last.elapsedSeconds * 1000).round());

  int get sampleCount => samples.length;

  double get peakCpm =>
      samples.isEmpty ? 0 : samples.map((s) => s.cpm).reduce((a, b) => a > b ? a : b);

  double get meanCpm => samples.isEmpty
      ? 0
      : samples.map((s) => s.cpm).reduce((a, b) => a + b) / samples.length;

  /// ปริมาณสะสมของ "ช่วงที่บันทึก" = ค่าสะสมท้ายลบค่าสะสมต้น
  /// (ค่าสะสมในไฟล์นับต่อจากตอนเชื่อมต่อ ไม่ได้เริ่มที่ศูนย์เสมอไป)
  double get totalUSv => samples.isEmpty
      ? 0
      : (samples.last.accumulatedUSv - samples.first.accumulatedUSv)
          .clamp(0, double.infinity);

  /// อ่านไฟล์ทั้งไฟล์ ใช้ทั้งหน้ารายการและหน้ารายละเอียด
  /// ไฟล์ 1 ชั่วโมงที่ 1 Hz มีราว 3600 บรรทัด (~250 KB) จึงอ่านทั้งไฟล์ได้โดยไม่ต้อง index
  /// คืน null ถ้าไฟล์ไม่ใช่รูปแบบของเรา
  static Future<SurveySession?> load(File file) async {
    try {
      final lines = await file.readAsLines();
      if (lines.isEmpty || !lines.first.startsWith('# telepole-session')) return null;

      DateTime? startedAt;
      var cpmPerUSvh = 0.0;
      String? note;
      for (final line in lines) {
        if (!line.startsWith('#')) break;
        final body = line.substring(1).trim();
        final split = body.indexOf('=');
        if (split < 0) continue;
        final key = body.substring(0, split);
        final value = body.substring(split + 1);
        if (key == 'started_at') startedAt = DateTime.tryParse(value);
        if (key == 'cpm_per_usvh') cpmPerUSvh = double.tryParse(value) ?? 0;
        if (key == 'note') note = value;
      }

      final samples = <SurveySample>[];
      for (final line in lines) {
        final sample = SurveySample.tryParse(line);
        if (sample != null) samples.add(sample);
      }

      return SurveySession(
        id: file.uri.pathSegments.last.replaceAll('.csv', ''),
        path: file.path,
        startedAt: startedAt ?? file.statSync().modified,
        cpmPerUSvh: cpmPerUSvh,
        note: note,
        samples: samples,
      );
    } on FileSystemException {
      return null;
    }
  }
}
