import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';

import '../services/telepole_connection.dart';
import '../theme.dart';
import 'dashboard_screen.dart';

/// หน้าค้นหา/เลือกอุปกรณ์ HC-05
/// HC-05 เป็น Bluetooth Classic — ปกติต้อง "จับคู่" (pair) ในหน้า Settings ก่อน
/// จึงแสดงทั้งรายการที่จับคู่แล้วและผลการ discovery
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _connection = TelepoleConnection();
  final List<BluetoothDevice> _devices = [];
  bool _scanning = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _connection.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _scanning = true;
      _status = null;
    });

    final granted = await TelepoleConnection.ensurePermissions();
    if (!granted) {
      setState(() {
        _scanning = false;
        _status = 'ไม่ได้รับสิทธิ์ Bluetooth / Location';
      });
      return;
    }

    final on = await TelepoleConnection.ensureBluetoothOn();
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

    // discovery เพิ่มเติมสำหรับอุปกรณ์ที่ยังไม่ได้จับคู่
    try {
      await for (final result in FlutterBluetoothSerial.instance.startDiscovery()) {
        if (!mounted) return;
        if (_devices.any((d) => d.address == result.device.address)) continue;
        setState(() => _devices.add(result.device));
      }
    } catch (_) {
      // discovery ล้มเหลวไม่ควรบล็อกการใช้งาน — รายการ bonded ยังใช้ต่อได้
    }

    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(BluetoothDevice device) async {
    await FlutterBluetoothSerial.instance.cancelDiscovery();
    if (!mounted) return;
    setState(() => _scanning = false);

    await _connection.connect(device);
    if (!mounted) return;

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('เลือกอุปกรณ์วัดรังสี'),
        actions: [
          IconButton(
            onPressed: _scanning ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'ค้นหาใหม่',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_scanning) const LinearProgressIndicator(minHeight: 2),
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
              child: Text(_status!, style: const TextStyle(color: AppTheme.danger)),
            ),
          Expanded(
            child: _devices.isEmpty && !_scanning
                ? const _EmptyHint()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: _devices.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final device = _devices[index];
                      final name = device.name ?? 'ไม่ทราบชื่อ';
                      final likely = name.toUpperCase().contains('HC-05') ||
                          name.toUpperCase().contains('TELEPOLE');
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
                            device.isBonded ? Icons.link : Icons.bluetooth_searching,
                            color: likely ? AppTheme.safe : AppTheme.textMuted,
                          ),
                          title: Text(name),
                          subtitle: Text(
                            '${device.address}${device.isBonded ? "  ·  จับคู่แล้ว" : ""}',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _connect(device),
                        ),
                      );
                    },
                  ),
          ),
        ],
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
            'ยังไม่พบอุปกรณ์\nกรุณาจับคู่ HC-05 ในหน้า Settings ของเครื่อง (PIN 1234 หรือ 0000) แล้วกดค้นหาใหม่',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
