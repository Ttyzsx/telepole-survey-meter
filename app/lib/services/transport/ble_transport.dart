import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import 'meter_transport.dart';

/// Bluetooth Low Energy สำหรับโมดูล "UART ใส" เช่น HM-10 / AT-09 / JDY-23
///
/// เป็นทางเดียวที่ iPhone ต่อกับ Arduino ได้ เพราะ iOS ไม่ให้แอปทั่วไปใช้
/// Bluetooth Classic (SPP) กับอุปกรณ์ที่ไม่ผ่านโปรแกรม MFi ของ Apple —
/// HC-05 จึงไม่โผล่ในรายการของ iPhone เลยไม่ว่าจะเขียนแอปอย่างไร
///
/// BLE ไม่มีท่อ serial ในตัวแบบ SPP โมดูลพวกนี้จำลองขึ้นมาด้วย characteristic:
/// ไบต์ที่ Arduino พ่นออก TX จะมาถึงเป็น notification ทีละก้อน (ราว 20 ไบต์)
/// ซึ่งไม่ตรงขอบบรรทัด — ผู้รับต้องต่อก้อนแล้วตัดที่ \n เอง เหมือนฝั่ง Classic
class BleTransport implements MeterTransport {
  static const Duration _scanTimeout = Duration(seconds: 14);
  static const Duration _connectTimeout = Duration(seconds: 12);

  /// ครั้งแรกบน iOS สถานะจะค้างที่ unknown จนกว่าผู้ใช้จะตอบกล่องขอสิทธิ์
  static const Duration _adapterTimeout = Duration(seconds: 20);

  /// service ของ UART ที่พบบ่อย เรียงตามที่น่าจะเจอ (รูปเต็ม 128 บิต ตัวพิมพ์เล็ก)
  static const List<String> _uartServices = [
    '0000ffe0-0000-1000-8000-00805f9b34fb', // HM-10, AT-09, JDY-08/23, HC-08
    '6e400001-b5a3-f393-e0a9-e50e24dcca9e', // Nordic UART (ESP32, nRF)
    '0000fff0-0000-1000-8000-00805f9b34fb', // โคลนบางรุ่น
  ];

  /// service มาตรฐานที่ทุกเครื่องมี ไม่ใช่ท่อข้อมูลของเรา
  static const List<String> _genericServicePrefixes = [
    '00001800-',
    '00001801-',
    '0000180a-',
  ];

  @override
  Future<String?> prepare() async {
    if (!await fbp.FlutterBluePlus.isSupported) {
      return 'เครื่องนี้ไม่รองรับ Bluetooth LE';
    }

    final state = await fbp.FlutterBluePlus.adapterState
        .where((s) =>
            s != fbp.BluetoothAdapterState.unknown &&
            s != fbp.BluetoothAdapterState.turningOn)
        .first
        .timeout(
          _adapterTimeout,
          onTimeout: () => fbp.BluetoothAdapterState.unknown,
        );

    switch (state) {
      case fbp.BluetoothAdapterState.on:
        return null;
      case fbp.BluetoothAdapterState.unauthorized:
        return 'ไม่ได้รับสิทธิ์ Bluetooth — เปิดให้แอปนี้ใน Settings ของเครื่อง';
      case fbp.BluetoothAdapterState.unknown:
        return 'ยังไม่ได้รับสิทธิ์ Bluetooth — อนุญาตแล้วกดค้นหาใหม่';
      default:
        return 'กรุณาเปิด Bluetooth';
    }
  }

  /// BLE ไม่มีขั้นตอนจับคู่ล่วงหน้าแบบ HC-05 จึงไม่มีรายการที่รู้จักอยู่ก่อน
  @override
  Future<List<MeterDevice>> knownDevices() async => const [];

  @override
  Stream<MeterDevice> scan() {
    // ไม่กรองด้วย service UUID เพราะโคลน HM-10 จำนวนมากไม่ประกาศ UUID ตอนโฆษณา
    unawaited(
      fbp.FlutterBluePlus.startScan(timeout: _scanTimeout)
          .catchError((Object _) {}),
    );
    return fbp.FlutterBluePlus.onScanResults
        .expand((results) => results)
        .map(_toMeterDevice)
        // อุปกรณ์ไร้ชื่อรอบตัวมีเป็นสิบ (หูฟัง นาฬิกา บีคอน) โมดูล UART มีชื่อเสมอ
        .where((device) => device.name.isNotEmpty);
  }

  @override
  Future<void> stopScan() async {
    await fbp.FlutterBluePlus.stopScan();
  }

  @override
  Future<MeterLink> connect(MeterDevice device) async {
    final remote = fbp.BluetoothDevice.fromId(device.id);
    try {
      await remote.connect(timeout: _connectTimeout);
      final uart = _findUart(await remote.discoverServices());
      if (uart == null) {
        throw const MeterLinkException(
          'อุปกรณ์นี้ไม่มีช่อง serial แบบ BLE — '
          'ต้องเป็นโมดูลอย่าง HM-10 / AT-09 / JDY-23',
        );
      }
      await uart.notify.setNotifyValue(true);
      return _BleLink(remote, uart.notify, uart.write);
    } on Object {
      // ต่อติดแล้วแต่ไปต่อไม่ได้ — ปล่อยอุปกรณ์ ไม่งั้นมันจะค้างสถานะ connected
      // และหยุดโฆษณา ทำให้ค้นหารอบถัดไปไม่เจอ
      try {
        await remote.disconnect();
      } on Exception {
        // ปล่อยไม่สำเร็จก็ไม่มีอะไรทำต่อได้ รายงานข้อผิดพลาดเดิมดีกว่า
      }
      rethrow;
    }
  }

  @override
  String get emptyHint =>
      'ยังไม่พบอุปกรณ์\n'
      'iPhone ต่อได้เฉพาะโมดูล Bluetooth LE (HM-10 / AT-09 / JDY-23)\n'
      'HC-05 เป็น Bluetooth Classic ซึ่ง iOS มองไม่เห็น\n'
      'เปิดเครื่องวัดแล้วกดค้นหาใหม่ — ไม่ต้องจับคู่ใน Settings ก่อน';

  MeterDevice _toMeterDevice(fbp.ScanResult result) {
    final advertised = result.advertisementData.advName;
    return MeterDevice(
      id: result.device.remoteId.str,
      name: advertised.isNotEmpty ? advertised : result.device.platformName,
      kind: MeterLinkKind.ble,
      rssi: result.rssi,
    );
  }

  /// หาคู่ characteristic ที่ใช้รับและส่ง ลอง service ที่รู้จักก่อน
  /// ถ้าไม่เจอค่อยรับ service ไหนก็ได้ที่ส่ง notification ได้
  static _Uart? _findUart(List<fbp.BluetoothService> services) {
    for (final known in _uartServices) {
      for (final service in services) {
        if (service.serviceUuid.str128.toLowerCase() != known) continue;
        final uart = _uartIn(service);
        if (uart != null) return uart;
      }
    }
    for (final service in services) {
      final uuid = service.serviceUuid.str128.toLowerCase();
      if (_genericServicePrefixes.any(uuid.startsWith)) continue;
      final uart = _uartIn(service);
      if (uart != null) return uart;
    }
    return null;
  }

  /// HM-10 ใช้ characteristic เดียว (FFE1) ทั้งรับและส่ง
  /// ส่วน JDY-23 กับ Nordic UART แยกเป็นสองตัว — เลือกตามความสามารถจึงครอบทั้งหมด
  static _Uart? _uartIn(fbp.BluetoothService service) {
    fbp.BluetoothCharacteristic? notify;
    fbp.BluetoothCharacteristic? write;
    for (final c in service.characteristics) {
      final p = c.properties;
      if (notify == null && (p.notify || p.indicate)) notify = c;
      if (write == null && (p.write || p.writeWithoutResponse)) write = c;
    }
    if (notify == null) return null;
    return _Uart(notify, write);
  }
}

class _Uart {
  final fbp.BluetoothCharacteristic notify;

  /// null ได้ — ยังอ่านค่าได้ปกติ แค่ส่งคำสั่งรีเซ็ตไปที่บอร์ดไม่ได้
  final fbp.BluetoothCharacteristic? write;

  const _Uart(this.notify, this.write);
}

class _BleLink implements MeterLink {
  final fbp.BluetoothDevice _remote;
  final fbp.BluetoothCharacteristic? _write;
  final StreamController<Uint8List> _input = StreamController<Uint8List>();
  late final StreamSubscription<List<int>> _valueSub;
  late final StreamSubscription<fbp.BluetoothConnectionState> _stateSub;

  _BleLink(this._remote, fbp.BluetoothCharacteristic notify, this._write) {
    _valueSub = notify.onValueReceived.listen(
      (bytes) => _input.add(Uint8List.fromList(bytes)),
      onError: _input.addError,
    );
    // notification stream ไม่จบเองเมื่อสัญญาณหลุด ต้องฟังสถานะแล้วปิดให้
    // ไม่งั้นแอปจะค้างหน้า "เชื่อมต่อแล้ว" ทั้งที่ไม่มีข้อมูลเข้า
    _stateSub = _remote.connectionState.listen((state) {
      if (state == fbp.BluetoothConnectionState.disconnected) {
        unawaited(_finish());
      }
    });
  }

  @override
  Stream<Uint8List> get input => _input.stream;

  @override
  void write(String text) {
    final target = _write;
    if (target == null || !_remote.isConnected) return;
    unawaited(
      target
          .write(
            utf8.encode(text),
            withoutResponse: target.properties.writeWithoutResponse,
          )
          .catchError((Object _) {}),
    );
  }

  Future<void> _finish() async {
    await _valueSub.cancel();
    await _stateSub.cancel();
    // ไม่ await — future ของ close() จะไม่จบถ้าไม่มีใครฟัง stream อยู่
    if (!_input.isClosed) unawaited(_input.close());
  }

  @override
  Future<void> close() async {
    await _finish();
    await _remote.disconnect();
  }
}
