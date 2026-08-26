import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_classic/flutter_blue_classic.dart';

import '../services/telepole_connection.dart';
import '../theme.dart';
import 'dashboard_screen.dart';

/// หน้าค้นหา/เลือกอุปกรณ์ HC-05
/// HC-05 เป็น Bluetooth Classic — ปกติต้อง "จับคู่" (pair) ในหน้า Settings ก่อน
/// จึงแสดงทั้งรายการที่จับคู่แล้วและผลการสแกน
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _connection = TelepoleConnection();
  final List<BluetoothDevice> _devices = [];
  StreamSubscription<BluetoothDevice>? _scanSub;
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
    TelepoleConnection.blue.stopScan();
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

    final granted = await TelepoleConnection.ensurePermissions();
    if (!mounted) return;
    if (!granted) {
      setState(() {
        _scanning = false;
        _status = 'ไม่ได้รับสิทธิ์ Bluetooth / Location';
      });
      return;
    }

    final on = await TelepoleConnection.ensureBluetoothOn();
    if (!mounted) return;
    if (!on) {
      setState(() {
        _scanning = false;
        _status = 'กรุณาเปิด Bluetooth';
      });
      return;
    }

    final bonded = await TelepoleConnection.bondedDevices();
    if (!mounted) return;
    setState(() {
      _devices
        ..clear()
        ..addAll(bonded);
    });

    // สแกนเพิ่มเติมสำหรับอุปกรณ์ที่ยังไม่ได้จับคู่
    _scanSub = TelepoleConnection.blue.scanResults.listen(
      (device) {
        if (!mounted) return;
        if (_devices.contains(device)) return;
        setState(() => _devices.add(device));
      },
      // สแกนล้มเหลวไม่ควรบล็อกการใช้งาน — รายการที่จับคู่แล้วยังใช้ต่อได้
      onError: (_) {},
    );
    TelepoleConnection.blue.startScan();

    // Android จำกัดเวลาสแกนอยู่แล้ว ตั้ง timer ไว้เพื่อคืนสถานะ UI
    Future.delayed(const Duration(seconds: 14), () {
      if (!mounted) return;
      TelepoleConnection.blue.stopScan();
      setState(() => _scanning = false);
    });
  }

  Future<void> _connect(BluetoothDevice device) async {
    TelepoleConnection.blue.stopScan();
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
                ? const _EmptyHint()
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
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final BluetoothDevice device;
  final VoidCallback? onTap;

  const _DeviceTile({required this.device, this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = device.alias ?? device.name ?? 'ไม่ทราบชื่อ';
    final upper = name.toUpperCase();
    // เดาว่าน่าจะเป็นเครื่องของเรา เพื่อให้หาเจอง่ายในรายการยาว ๆ
    final likely = upper.contains('HC-05') || upper.contains('TELEPOLE');
    final bonded = device.bondState == BluetoothBondState.bonded;

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
          '${device.address}${bonded ? "  ·  จับคู่แล้ว" : ""}'
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
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bluetooth_disabled, size: 48, color: AppTheme.textMuted),
          SizedBox(height: 16),
          Text(
            'ยังไม่พบอุปกรณ์\n'
            'กรุณาจับคู่ HC-05 ในหน้า Settings ของเครื่อง (PIN 1234 หรือ 0000) '
            'แล้วกดค้นหาใหม่',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
