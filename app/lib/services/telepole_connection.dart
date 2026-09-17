import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/reading.dart';

enum LinkState { idle, connecting, connected, disconnected, error }

/// จัดการการเชื่อมต่อ Bluetooth Classic (SPP) กับ HC-05
/// แปลง byte stream เป็น [Reading] ทีละบรรทัด และเป็นเจ้าของค่าที่ derive มาจาก CPM
class TelepoleConnection extends ChangeNotifier {
  static final FlutterBlueClassic blue = FlutterBlueClassic();

  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _sub;
  String _rxBuffer = '';

  LinkState _state = LinkState.idle;
  String? _errorMessage;
  BluetoothDevice? _device;
  Reading? _latest;

  final List<Reading> _history = [];
  static const int maxHistory = 300; // เก็บย้อนหลัง 5 นาที ที่ 1 Hz

  MeterCalibration _calibration = const MeterCalibration();

  // โหมดสาธิต: สร้างข้อมูลปลอมในเครื่อง ใช้ทดสอบ UI ได้โดยไม่ต้องมีฮาร์ดแวร์
  Timer? _demoTimer;
  final Random _random = Random();
  double _demoBaseCpm = 25;
  bool _isDemo = false;

  // ค่าสะสมที่แอปอินทิเกรตเอง เพื่อให้เปลี่ยน sensitivity ได้โดยไม่ต้อง flash บอร์ดใหม่
  double _accumulatedUSv = 0;
  DateTime? _lastIntegratedAt;

  LinkState get state => _state;
  String? get errorMessage => _errorMessage;
  BluetoothDevice? get device => _device;
  Reading? get latest => _latest;
  List<Reading> get history => List.unmodifiable(_history);
  bool get isConnected => _state == LinkState.connected;
  bool get isDemo => _isDemo;
  double get demoBaseCpm => _demoBaseCpm;

  MeterCalibration get calibration => _calibration;

  /// ค่า uSv/h ที่แอปคำนวณเองจาก CPM ล่าสุด
  double get doseRate =>
      _latest == null ? 0 : _calibration.doseRateFor(_latest!.cpm);

  /// ปริมาณสะสม (uSv) ที่แอปอินทิเกรตเอง
  double get accumulatedUSv => _accumulatedUSv;

  /// เปลี่ยนค่าสอบเทียบ แล้ว rescale ค่าสะสมที่ผ่านมาให้สอดคล้องกับค่าใหม่
  /// (ไม่งั้นค่าสะสมจะเป็นการผสมกันของสองสเกล ซึ่งอ่านแล้วตีความไม่ได้)
  void setCalibration(MeterCalibration next) {
    if (next.cpmPerUSvh <= 0) return;
    final previous = _calibration.cpmPerUSvh;
    _calibration = next;
    if (previous > 0) {
      _accumulatedUSv *= previous / next.cpmPerUSvh;
    }
    notifyListeners();
  }

  /// เริ่มโหมดสาธิต — ป้อนค่าจำลองเข้าทางเดียวกับข้อมูลจริงทุกประการ
  /// (ผ่าน _integrate และ _history) เพื่อให้สิ่งที่เห็นบนจอสะท้อนโค้ดเส้นทางจริง
  void startDemo() {
    _isDemo = true;
    _history.clear();
    _accumulatedUSv = 0;
    _lastIntegratedAt = null;
    _setState(LinkState.connected);

    _demoTimer?.cancel();
    _demoTimer = Timer.periodic(const Duration(seconds: 1), (_) => _emitDemoReading());
  }

  /// ปรับระดับรังสีจำลอง เพื่อทดสอบว่าแถบเตือนและเสียงทำงานถูกต้อง
  void setDemoBaseCpm(double cpm) {
    _demoBaseCpm = cpm.clamp(0, 5000);
    notifyListeners();
  }

  void _emitDemoReading() {
    // การสลายตัวของสารกัมมันตรังสีเป็นกระบวนการสุ่มแบบปัวซง
    // ความเบี่ยงเบนมาตรฐานของจำนวนนับ = รากที่สองของค่าเฉลี่ย
    // จำลองด้วยการกระจายแบบปกติที่มี sigma = sqrt(mean) ซึ่งใกล้เคียงพอเมื่อค่าไม่น้อยมาก
    final sigma = sqrt(_demoBaseCpm.clamp(1, double.infinity));
    final noisy = (_demoBaseCpm + _gaussian() * sigma).clamp(0.0, 99999.0);

    final reading = Reading(
      cpm: noisy,
      deviceDoseRate: _calibration.doseRateFor(noisy),
      deviceAccumulated: _accumulatedUSv,
      cps: _poisson(_demoBaseCpm / 60.0),
      timestamp: DateTime.now(),
    );

    _integrate(reading);
    _latest = reading;
    _history.add(reading);
    if (_history.length > maxHistory) {
      _history.removeRange(0, _history.length - maxHistory);
    }
    notifyListeners();
  }

  /// สุ่มจำนวนเหตุการณ์ในหนึ่งช่วงเวลาตามการแจกแจงปัวซง (อัลกอริทึมของ Knuth)
  /// ใช้กับค่า CPS จำลอง เพราะจำนวนพัลส์ต่อวินาทีเป็นจำนวนเต็มที่กระจายแบบนี้จริง
  int _poisson(double lambda) {
    if (lambda <= 0) return 0;
    // lambda สูง ๆ วิธีของ Knuth จะช้าและ exp(-lambda) จะลู่เข้าศูนย์จนคำนวณไม่ได้
    // ที่ระดับนั้นการแจกแจงปกติแทนได้ใกล้เคียงมากอยู่แล้ว
    if (lambda > 30) {
      final approx = lambda + _gaussian() * sqrt(lambda);
      return approx < 0 ? 0 : approx.round();
    }
    final threshold = exp(-lambda);
    var count = 0;
    var product = _random.nextDouble();
    while (product > threshold) {
      count++;
      product *= _random.nextDouble();
    }
    return count;
  }

  /// สุ่มค่าจากการกระจายแบบปกติ ค่าเฉลี่ย 0 ส่วนเบี่ยงเบน 1 (Box-Muller)
  double _gaussian() {
    final u1 = 1.0 - _random.nextDouble(); // เลี่ยง log(0)
    final u2 = _random.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2.0 * pi * u2);
  }

  /// ขอ permission ที่จำเป็น (Android 12+ ใช้ BLUETOOTH_CONNECT/SCAN,
  /// ต่ำกว่านั้นใช้ location)
  static Future<bool> ensurePermissions() async {
    final results = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    // บาง OS จะคืน permanentlyDenied สำหรับ permission ที่ไม่มีอยู่จริงในเวอร์ชันนั้น
    return results[Permission.bluetoothConnect]?.isGranted == true ||
        results[Permission.location]?.isGranted == true;
  }

  static Future<List<BluetoothDevice>> bondedDevices() async {
    try {
      return await blue.bondedDevices ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> ensureBluetoothOn() async {
    try {
      if (await blue.isEnabled) return true;
      return await blue.turnOn();
    } catch (_) {
      return false;
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    await disconnect();

    _device = device;
    _setState(LinkState.connecting);

    try {
      final connection = await blue.connect(device.address);
      if (connection == null) {
        _fail('เชื่อมต่อไม่สำเร็จ — ตรวจสอบว่าจับคู่ HC-05 แล้วและเครื่องเปิดอยู่');
        return;
      }
      _connection = connection;
      _rxBuffer = '';
      _lastIntegratedAt = null;
      _sub = connection.input?.listen(
        _onData,
        onDone: () => _setState(LinkState.disconnected),
        onError: (Object e) => _fail('การเชื่อมต่อขาดหาย: $e'),
        cancelOnError: true,
      );
      _setState(LinkState.connected);
    } catch (e) {
      _fail('เชื่อมต่อไม่สำเร็จ: $e');
    }
  }

  void _onData(Uint8List data) {
    // ข้อมูลมาเป็น chunk ไม่ตรงขอบบรรทัด จึงต้อง buffer แล้วตัดที่ \n
    _rxBuffer += utf8.decode(data, allowMalformed: true);

    // กันบัฟเฟอร์บวมถ้าอุปกรณ์ส่งข้อมูลผิดรูปแบบและไม่มี newline เลย
    if (_rxBuffer.length > 4096) {
      _rxBuffer = _rxBuffer.substring(_rxBuffer.length - 512);
    }

    final lines = _rxBuffer.split('\n');
    _rxBuffer = lines.removeLast(); // ท่อนสุดท้ายอาจยังไม่จบบรรทัด

    var updated = false;
    for (final line in lines) {
      final reading = Reading.tryParse(line);
      if (reading == null) continue;
      _integrate(reading);
      _latest = reading;
      _history.add(reading);
      if (_history.length > maxHistory) {
        _history.removeRange(0, _history.length - maxHistory);
      }
      updated = true;
    }
    if (updated) notifyListeners();
  }

  /// สะสมปริมาณรังสี: uSv += uSv/h * (ช่วงเวลาจริงเป็นชั่วโมง)
  /// ใช้ช่วงเวลาที่วัดได้จริงแทนการสมมติว่า 1 วินาทีเป๊ะ เพราะแพ็กเก็ตอาจมาช้า
  void _integrate(Reading reading) {
    final previous = _lastIntegratedAt;
    _lastIntegratedAt = reading.timestamp;
    if (previous == null) return;

    final deltaMs = reading.timestamp.difference(previous).inMilliseconds;
    // ข้ามช่วงที่ผิดปกติ (สัญญาณหลุดไปนานแล้วกลับมา) ไม่งั้นค่าสะสมจะพุ่งผิด
    // เพดาน 30 วิ เพราะ gm_final ส่งทุก 10 วิ ถ้าตั้ง 10 วิพอดี รอบที่ช้าไปนิดเดียวจะถูกทิ้ง
    if (deltaMs <= 0 || deltaMs > 30000) return;

    _accumulatedUSv +=
        _calibration.doseRateFor(reading.cpm) * (deltaMs / 3600000.0);
  }

  void _send(String command) {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;
    connection.writeString(command);
  }

  /// รีเซ็ตค่าสะสมทั้งฝั่งแอปและฝั่ง firmware ('R')
  Future<void> resetAccumulated() async {
    _accumulatedUSv = 0;
    _lastIntegratedAt = null;
    notifyListeners();
    _send('R');
  }

  /// รีเซ็ตทุกอย่างรวมถึงหน้าต่างเฉลี่ย CPM ใน firmware ('Z')
  Future<void> resetAll() async {
    _accumulatedUSv = 0;
    _lastIntegratedAt = null;
    _history.clear();
    notifyListeners();
    _send('Z');
  }

  Future<void> disconnect() async {
    _demoTimer?.cancel();
    _demoTimer = null;
    _isDemo = false;
    await _sub?.cancel();
    _sub = null;
    try {
      await _connection?.close();
    } catch (_) {
      // ปิดไม่สำเร็จไม่ควรทำให้ UI ค้าง — ปล่อยผ่านแต่ยังเคลียร์ state
    }
    _connection = null;
    if (_state != LinkState.idle) _setState(LinkState.disconnected);
  }

  void _setState(LinkState s) {
    _state = s;
    if (s != LinkState.error) _errorMessage = null;
    notifyListeners();
  }

  void _fail(String message) {
    _errorMessage = message;
    _state = LinkState.error;
    notifyListeners();
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _sub?.cancel();
    _connection?.dispose();
    super.dispose();
  }
}
