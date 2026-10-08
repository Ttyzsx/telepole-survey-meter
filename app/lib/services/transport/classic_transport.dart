import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';
import 'package:permission_handler/permission_handler.dart';

import 'meter_transport.dart';

/// Bluetooth Classic (SPP) สำหรับ HC-05 — ใช้ได้บน Android เท่านั้น
class ClassicTransport implements MeterTransport {
  final FlutterBlueClassic _blue = FlutterBlueClassic();

  @override
  Future<String?> prepare() async {
    if (!await _ensurePermissions()) {
      return 'ไม่ได้รับสิทธิ์ Bluetooth / Location';
    }
    if (!await _ensureBluetoothOn()) return 'กรุณาเปิด Bluetooth';
    return null;
  }

  /// Android 12+ ใช้ BLUETOOTH_CONNECT/SCAN, ต่ำกว่านั้นใช้ location
  Future<bool> _ensurePermissions() async {
    final results = await [
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
      Permission.location,
    ].request();
    // บาง OS จะคืน permanentlyDenied สำหรับ permission ที่ไม่มีอยู่จริงในเวอร์ชันนั้น
    return results[Permission.bluetoothConnect]?.isGranted == true ||
        results[Permission.location]?.isGranted == true;
  }

  Future<bool> _ensureBluetoothOn() async {
    try {
      if (await _blue.isEnabled) return true;
      return await _blue.turnOn();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<MeterDevice>> knownDevices() async {
    try {
      final bonded = await _blue.bondedDevices ?? const [];
      return bonded.map(_toMeterDevice).toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Stream<MeterDevice> scan() {
    _blue.startScan();
    return _blue.scanResults.map(_toMeterDevice);
  }

  @override
  Future<void> stopScan() async {
    _blue.stopScan();
  }

  @override
  Future<MeterLink> connect(MeterDevice device) async {
    final connection = await _blue.connect(device.id);
    if (connection == null) {
      throw const MeterLinkException(
        'เชื่อมต่อไม่สำเร็จ — ตรวจสอบว่าจับคู่ HC-05 แล้วและเครื่องเปิดอยู่',
      );
    }
    return _ClassicLink(connection);
  }

  @override
  String get emptyHint =>
      'ยังไม่พบอุปกรณ์\n'
      'กรุณาจับคู่ HC-05 ในหน้า Settings ของเครื่อง (PIN 1234 หรือ 0000) '
      'แล้วกดค้นหาใหม่';

  MeterDevice _toMeterDevice(BluetoothDevice device) => MeterDevice(
        id: device.address,
        name: device.alias ?? device.name ?? 'ไม่ทราบชื่อ',
        kind: MeterLinkKind.classic,
        rssi: device.rssi,
        isBonded: device.bondState == BluetoothBondState.bonded,
      );
}

class _ClassicLink implements MeterLink {
  final BluetoothConnection _connection;

  _ClassicLink(this._connection);

  @override
  Stream<Uint8List> get input =>
      _connection.input ?? const Stream<Uint8List>.empty();

  @override
  void write(String text) {
    if (!_connection.isConnected) return;
    _connection.writeString(text);
  }

  @override
  Future<void> close() async {
    try {
      await _connection.close();
    } finally {
      _connection.dispose();
    }
  }
}
