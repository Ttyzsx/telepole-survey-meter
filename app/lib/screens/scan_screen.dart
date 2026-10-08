import 'dart:async';

import 'package:flutter/material.dart';

import '../services/telepole_connection.dart';
import '../services/transport/meter_transport.dart';
import '../theme.dart';
import 'dashboard_screen.dart';

/// หน้าค้นหา/เลือกหัววัด
/// HC-05 (Bluetooth Classic, Android) ปกติต้อง "จับคู่" ในหน้า Settings ก่อน
/// จึงแสดงทั้งรายการที่จับคู่แล้วและผลการสแกน
/// ส่วนโมดูล BLE ไม่ต้องจับคู่ โผล่จากการสแกนอย่างเดียว
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _connection = TelepoleConnection();
  final List<MeterDevice> _devices = [];
  StreamSubscription<MeterDevice>? _scanSub;
  bool _scanning = false;
  bool _connecting = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _connection.transport.stopScan();
    _connection.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await _scanSub?.cancel();
    _scanSub = null;

    setState(() {
      _scanning = true;
      _status = null;
    });

    final transport = _connection.transport;
    final problem = await transport.prepare();
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _scanning = false;
        _status = problem;
      });
      return;
    }

    final known = await transport.knownDevices();
    if (!mounted) return;
    setState(() {
      _devices
        ..clear()
        ..addAll(known);
    });

    // สแกนเพิ่มเติมสำหรับอุปกรณ์ที่ยังไม่ได้จับคู่
    _scanSub = transport.scan().listen(
      (device) {
        if (!mounted) return;
        if (_devices.contains(device)) return;
        setState(() => _devices.add(device));
      },
      // สแกนล้มเหลวไม่ควรบล็อกการใช้งาน — รายการที่จับคู่แล้วยังใช้ต่อได้
      onError: (_) {},
    );

    // ระบบจำกัดเวลาสแกนอยู่แล้ว ตั้ง timer ไว้เพื่อคืนสถานะ UI
    Future.delayed(const Duration(seconds: 14), () {
      if (!mounted) return;
      transport.stopScan();
      setState(() => _scanning = false);
    });
  }

  Future<void> _startDemo() async {
    await _connection.transport.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
    setState(() => _scanning = false);

    _connection.startDemo();
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DashboardScreen(connection: _connection)),
    );
    await _connection.disconnect();
  }

  Future<void> _connect(MeterDevice device) async {
    await _connection.transport.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;

    setState(() {
      _scanning = false;
      _connecting = true;
      _status = null;
    });

    await _connection.connect(device);
    if (!mounted) return;
    setState(() => _connecting = false);

    if (!_connection.isConnected) {
      setState(() => _status = _connection.errorMessage ?? 'เชื่อมต่อไม่สำเร็จ');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DashboardScreen(connection: _connection)),
    );
    await _connection.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _scanning || _connecting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('เลือกอุปกรณ์วัดรังสี'),
        actions: [
          IconButton(
            onPressed: busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'ค้นหาใหม่',
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 2),
          if (_status != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.12),
                border: Border.all(color: AppTheme.danger.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _status!,
                style: const TextStyle(color: AppTheme.danger),
              ),
            ),
          Expanded(
            child: _devices.isEmpty && !busy
                ? _EmptyHint(message: _connection.transport.emptyHint)
                : ListView.separated(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _devices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) =>
                        _DeviceTile(
                      device: _devices[index],
                      onTap: _connecting ? null : () => _connect(_devices[index]),
                    ),
                  ),
          ),
          _DemoBar(onTap: busy ? null : _startDemo),
        ],
      ),
    );
  }
}

/// ทางเข้าโหมดสาธิต — ให้ลองใช้แอปได้โดยไม่ต้องมีฮาร์ดแวร์
class _DemoBar extends StatelessWidget {
  final VoidCallback? onTap;

  const _DemoBar({this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.science_outlined, size: 18),
          label: const Text('โหมดสาธิต (ไม่ต้องต่ออุปกรณ์)'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            foregroundColor: AppTheme.textMuted,
            side: const BorderSide(color: AppTheme.outline),
          ),
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  /// ชื่อโรงงานของโมดูลบลูทูธที่ใช้กับ Arduino ทั้งแบบ Classic และ BLE
  static const List<String> _likelyNames = [
    'TELEPOLE',
    'HC-0',
    'HMSOFT',
    'BT05',
    'AT-09',
    'JDY',
    'MLT-BT',
  ];

  final MeterDevice device;
  final VoidCallback? onTap;

  const _DeviceTile({required this.device, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = device.name;
    final upper = name.toUpperCase();
    // เดาว่าน่าจะเป็นเครื่องของเรา เพื่อให้หาเจอง่ายในรายการยาว ๆ
    final likely = _likelyNames.any(upper.contains);
    final bonded = device.isBonded;
    // id ของ BLE บน iOS เป็น UUID ยาวที่ระบบสุ่มให้ ไม่มีความหมายกับผู้ใช้
    final label = device.kind == MeterLinkKind.ble ? 'BLE' : device.id;

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: likely ? AppTheme.safe.withOpacity(0.5) : AppTheme.outline,
          ),
        ),
        leading: Icon(
          bonded ? Icons.link : Icons.bluetooth_searching,
          color: likely ? AppTheme.safe : AppTheme.textMuted,
        ),
        title: Text(name),
        subtitle: Text(
          '$label${bonded ? "  ·  จับคู่แล้ว" : ""}'
          '${device.rssi != null ? "  ·  ${device.rssi} dBm" : ""}',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String message;

  const _EmptyHint({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.bluetooth_disabled,
            size: 48,
            color: AppTheme.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
