import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/reading.dart';

enum LinkState { idle, connecting, connected, disconnected, error }

/// จัดการการเชื่อมต่อ Bluetooth Classic (SPP) กับ HC-05
/// แปลง byte stream เป็น [Reading] ทีละบรรทัด และเป็นเจ้าของค่าที่ derive มาจาก CPM
class TelepoleConnection extends ChangeNotifier {
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

  // ค่าสะสมที่แอปอินทิเกรตเอง เพื่อให้เปลี่ยน sensitivity ได้โดยไม่ต้อง flash บอร์ดใหม่
  double _accumulatedUSv = 0;
  DateTime? _lastIntegratedAt;

  LinkState get state => _state;
  String? get errorMessage => _errorMessage;
  BluetoothDevice? get device => _device;
  Reading? get latest => _latest;
  List<Reading> get history => List.unmodifiable(_history);
  bool get isConnected => _state == LinkState.connected;

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
      return await FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (_) {
      return const [];
    }
  }

  static Future<bool> ensureBluetoothOn() async {
    final enabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
    if (enabled) return true;
    return await FlutterBluetoothSerial.instance.requestEnable() ?? false;
  }

  Future<void> connect(BluetoothDevice device) async {
    await disconnect();

    _device = device;
    _setState(LinkState.connecting);

    try {
      final connection = await BluetoothConnection.toAddress(device.address);
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
    if (deltaMs <= 0 || deltaMs > 10000) return;

    _accumulatedUSv +=
        _calibration.doseRateFor(reading.cpm) * (deltaMs / 3600000.0);
  }

  Future<void> _send(String command) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) return;
    connection.output.add(Uint8List.fromList(utf8.encode(command)));
    await connection.output.allSent;
  }

  /// รีเซ็ตค่าสะสมทั้งฝั่งแอปและฝั่ง firmware ('R')
  Future<void> resetAccumulated() async {
    _accumulatedUSv = 0;
    _lastIntegratedAt = null;
    notifyListeners();
    await _send('R');
  }

  /// รีเซ็ตทุกอย่างรวมถึงหน้าต่างเฉลี่ย CPM ใน firmware ('Z')
  Future<void> resetAll() async {
    _accumulatedUSv = 0;
    _lastIntegratedAt = null;
    _history.clear();
    notifyListeners();
    await _send('Z');
  }

  Future<void> disconnect() async {
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
    _sub?.cancel();
    _connection?.close();
    super.dispose();
  }
}
