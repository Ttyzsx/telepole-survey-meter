import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/reading.dart';
import '../models/survey_session.dart';

/// บันทึกค่าที่วัดได้ลงไฟล์ CSV หนึ่งไฟล์ต่อการสำรวจหนึ่งครั้ง
///
/// เขียนลงไฟล์ทันทีทีละบรรทัด ไม่รอจบแล้วค่อยเซฟทีเดียว
/// เพราะงานภาคสนามแบตหมดหรือแอปถูกระบบฆ่ากลางคันได้ ถ้าเก็บไว้ในหน่วยความจำอย่างเดียวจะเสียทั้งชุด
/// ไฟล์ที่ถูกตัดกลางคันยังเปิดดูส่วนที่บันทึกไปแล้วได้ปกติ
class SessionRecorder extends ChangeNotifier {
  static const String _dirName = 'telepole_sessions';

  IOSink? _sink;
  File? _file;
  DateTime? _startedAt;
  DateTime? _lastSampleAt;
  int _sampleCount = 0;
  double _peakCpm = 0;
  String? _error;

  bool get isRecording => _sink != null;
  int get sampleCount => _sampleCount;
  double get peakCpm => _peakCpm;
  String? get error => _error;

  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    return (_lastSampleAt ?? DateTime.now()).difference(started);
  }

  /// เก็บไว้ใน external app dir (`Android/data/<pkg>/files`) เป็นอันดับแรก
  /// เพราะเสียบสาย USB แล้วลากไฟล์เข้าคอมได้เลย ไม่ต้องรูท ไม่ต้องขอ permission
  /// ถ้าเครื่องไม่มี external storage ค่อยตกไปใช้ที่เก็บภายในแอป
  static Future<Directory> sessionsDirectory() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } on Object {
      base = null; // บาง OS ไม่รองรับ — ใช้ที่เก็บภายในแทน
    }
    base ??= await getApplicationDocumentsDirectory();

    final dir = Directory('${base.path}/$_dirName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// เริ่มบันทึก คืน true ถ้าเปิดไฟล์สำเร็จ
  Future<bool> start({required MeterCalibration calibration, String? note}) async {
    if (isRecording) return true;

    try {
      final dir = await sessionsDirectory();
      final startedAt = DateTime.now();
      final file = File('${dir.path}/${_fileNameFor(startedAt)}.csv');
      final sink = file.openWrite(mode: FileMode.writeOnly);
      sink.write(SurveySession.headerFor(
        startedAt: startedAt,
        cpmPerUSvh: calibration.cpmPerUSvh,
        note: note,
      ));

      _file = file;
      _sink = sink;
      _startedAt = startedAt;
      _lastSampleAt = null;
      _sampleCount = 0;
      _peakCpm = 0;
      _error = null;
      notifyListeners();
      return true;
    } on FileSystemException catch (e) {
      _error = 'เปิดไฟล์บันทึกไม่ได้: ${e.message}';
      notifyListeners();
      return false;
    }
  }

  /// เรียกทุกครั้งที่ได้ค่าใหม่ — ไม่ทำอะไรถ้ายังไม่ได้กดบันทึก
  void add(
    Reading reading, {
    required double doseRate,
    required double accumulatedUSv,
  }) {
    final sink = _sink;
    final started = _startedAt;
    if (sink == null || started == null) return;

    final sample = SurveySample(
      timestamp: reading.timestamp,
      elapsedSeconds:
          reading.timestamp.difference(started).inMilliseconds / 1000.0,
      cpm: reading.cpm,
      cps: reading.cps,
      doseRate: doseRate,
      accumulatedUSv: accumulatedUSv,
    );

    try {
      sink.writeln(sample.toCsvRow());
    } on StateError {
      // sink ถูกปิดไปแล้วระหว่างที่ค่าค้างอยู่ใน stream — ปล่อยผ่าน ไม่ควรทำให้ UI ล้ม
      return;
    }

    _sampleCount++;
    _lastSampleAt = reading.timestamp;
    if (reading.cpm > _peakCpm) _peakCpm = reading.cpm;
    notifyListeners();
  }

  /// หยุดบันทึกและปิดไฟล์ คืนข้อมูลที่บันทึกได้ (null ถ้าไม่มีข้อมูลเลย)
  Future<SurveySession?> stop() async {
    final sink = _sink;
    final file = _file;
    _sink = null;
    _file = null;
    _startedAt = null;
    notifyListeners();

    if (sink == null || file == null) return null;
    try {
      await sink.flush();
      await sink.close();
    } on Object {
      // ปิดไม่สำเร็จก็ยังพยายามอ่านสิ่งที่เขียนลงไปแล้ว
    }

    // ไม่มีตัวอย่างเลย = กดเริ่มแล้วกดหยุดทันที ไม่ต้องเก็บไฟล์เปล่าไว้รก
    if (_sampleCount == 0) {
      try {
        await file.delete();
      } on FileSystemException {
        // ลบไม่ได้ก็ไม่เป็นไร ไฟล์เปล่าไม่ทำให้อะไรพัง
      }
      return null;
    }

    return SurveySession.load(file);
  }

  /// รายการที่บันทึกไว้ทั้งหมด เรียงจากใหม่ไปเก่า
  static Future<List<SurveySession>> listSessions() async {
    final dir = await sessionsDirectory();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.csv'))
        .cast<File>()
        .toList();

    final sessions = <SurveySession>[];
    for (final file in files) {
      final session = await SurveySession.load(file);
      if (session != null) sessions.add(session);
    }
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sessions;
  }

  static Future<void> delete(SurveySession session) async {
    try {
      await File(session.path).delete();
    } on FileSystemException {
      // ไฟล์หายไปแล้วก็ถือว่าลบสำเร็จ
    }
  }

  /// ชื่อไฟล์เรียงตามเวลาได้ด้วยการเรียงตัวอักษร และไม่มีอักขระที่ระบบไฟล์ไม่ชอบ
  static String _fileNameFor(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return 'telepole-${t.year}${two(t.month)}${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  @override
  void dispose() {
    _sink?.close().catchError((_) {});
    super.dispose();
  }
}
