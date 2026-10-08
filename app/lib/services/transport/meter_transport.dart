import 'dart:async';

import 'package:flutter/foundation.dart';

import 'ble_transport.dart';
import 'classic_transport.dart';

/// ชนิดของลิงก์บลูทูธ — สองแบบนี้เป็นคนละโปรโตคอลกัน คุยข้ามกันไม่ได้
///
/// classic = SPP แบบ HC-05 (Android เท่านั้น — iOS ปิดไม่ให้แอปทั่วไปใช้)
/// ble     = Bluetooth Low Energy แบบ HM-10 / AT-09 / JDY-23 (ได้ทั้ง iOS และ Android)
enum MeterLinkKind { classic, ble }

/// อุปกรณ์ที่ค้นเจอ ในรูปที่ไม่ผูกกับไลบรารีบลูทูธตัวไหน
@immutable
class MeterDevice {
  /// MAC address บน Android · UUID ที่ iOS สุ่มให้ (iOS ไม่เปิดเผย MAC จริง)
  final String id;
  final String name;
  final MeterLinkKind kind;
  final int? rssi;
  final bool isBonded;

  const MeterDevice({
    required this.id,
    required this.name,
    required this.kind,
    this.rssi,
    this.isBonded = false,
  });

  // เทียบแค่ id กับ kind — ระหว่างสแกน อุปกรณ์เดิมจะถูกรายงานซ้ำด้วย rssi ใหม่เรื่อย ๆ
  @override
  bool operator ==(Object other) =>
      other is MeterDevice && other.id == id && other.kind == kind;

  @override
  int get hashCode => Object.hash(id, kind);
}

/// ท่อ serial ที่เปิดอยู่กับหัววัด — ไบต์เข้า ข้อความออก
abstract class MeterLink {
  /// ปิด stream (onDone) เมื่อการเชื่อมต่อหลุด
  Stream<Uint8List> get input;

  void write(String text);

  Future<void> close();
}

/// ข้อผิดพลาดที่มีข้อความพร้อมแสดงให้ผู้ใช้อ่าน
class MeterLinkException implements Exception {
  final String message;

  const MeterLinkException(this.message);

  @override
  String toString() => message;
}

/// วิธีค้นหาและเชื่อมต่อหัววัด แยกออกมาเพื่อให้ส่วนที่เหลือของแอปไม่ต้องรู้ว่า
/// ข้างล่างเป็น Bluetooth Classic หรือ BLE
abstract class MeterTransport {
  /// เลือกตามแพลตฟอร์ม: iOS ใช้ได้แต่ BLE · Android ใช้ได้ทั้งคู่
  /// จึงค้นหาสองแบบพร้อมกัน เครื่องเดียวกันจะเปลี่ยนโมดูลเป็น BLE ทีหลังก็ยังต่อได้
  factory MeterTransport.forPlatform() {
    if (defaultTargetPlatform == TargetPlatform.iOS) return BleTransport();
    return CompositeTransport(ClassicTransport(), BleTransport());
  }

  /// ขอสิทธิ์และตรวจว่าบลูทูธเปิดอยู่ คืน null ถ้าพร้อม ไม่งั้นคืนข้อความบอกผู้ใช้
  Future<String?> prepare();

  /// อุปกรณ์ที่ระบบรู้จักอยู่แล้วโดยไม่ต้องสแกน (ที่จับคู่ไว้)
  Future<List<MeterDevice>> knownDevices();

  /// เริ่มสแกน อุปกรณ์เดิมอาจถูกส่งซ้ำได้ ผู้รับต้องกรองเอง
  Stream<MeterDevice> scan();

  Future<void> stopScan();

  /// โยน [MeterLinkException] ถ้าต่อไม่ได้ด้วยเหตุที่อธิบายให้ผู้ใช้ฟังได้
  Future<MeterLink> connect(MeterDevice device);

  /// คำแนะนำที่แสดงเมื่อค้นแล้วไม่เจออะไรเลย
  String get emptyHint;
}

/// ค้นหาผ่านสอง transport พร้อมกัน แล้วส่งต่อการเชื่อมต่อไปยังตัวที่ตรงชนิด
///
/// [primary] เป็นตัวตัดสินว่าพร้อมใช้งานหรือไม่ ส่วน [secondary] เป็นของแถม —
/// ถ้ามันสแกนไม่ได้ก็เงียบไป ไม่ให้ไปขวางเส้นทางหลักที่ใช้งานได้อยู่
class CompositeTransport implements MeterTransport {
  final MeterTransport primary;
  final MeterTransport secondary;

  CompositeTransport(this.primary, this.secondary);

  @override
  Future<String?> prepare() => primary.prepare();

  @override
  Future<List<MeterDevice>> knownDevices() => primary.knownDevices();

  @override
  Stream<MeterDevice> scan() {
    final subs = <StreamSubscription<MeterDevice>>[];
    late final StreamController<MeterDevice> controller;
    controller = StreamController<MeterDevice>(
      onListen: () {
        subs.add(primary.scan().listen(
              controller.add,
              onError: controller.addError,
            ));
        try {
          subs.add(secondary.scan().listen(controller.add, onError: (_) {}));
        } on Exception {
          // secondary ใช้ไม่ได้บนเครื่องนี้ — ผลของ primary ยังไหลต่อตามปกติ
        }
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    await primary.stopScan();
    try {
      await secondary.stopScan();
    } on Exception {
      // เหตุผลเดียวกับใน scan()
    }
  }

  @override
  Future<MeterLink> connect(MeterDevice device) =>
      device.kind == MeterLinkKind.ble
          ? secondary.connect(device)
          : primary.connect(device);

  @override
  String get emptyHint => primary.emptyHint;
}
