import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/reading.dart';
import '../services/alarm_service.dart';
import '../services/telepole_connection.dart';
import '../theme.dart';
import '../widgets/calibration_sheet.dart';
import '../widgets/trend_chart.dart';

class DashboardScreen extends StatefulWidget {
  final TelepoleConnection connection;

  const DashboardScreen({super.key, required this.connection});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _alarm = AlarmService();
  Thresholds _thresholds = const Thresholds();

  @override
  void initState() {
    super.initState();
    _alarm.init();
    widget.connection.addListener(_onReading);
  }

  @override
  void dispose() {
    widget.connection.removeListener(_onReading);
    _alarm.dispose();
    super.dispose();
  }

  void _onReading() {
    if (widget.connection.latest == null) return;
    _alarm.update(_thresholds.levelFor(widget.connection.doseRate));
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('รีเซ็ตค่าสะสม?'),
        content: const Text('ค่าปริมาณรังสีสะสม (uSv) จะเริ่มนับใหม่จากศูนย์'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('รีเซ็ต'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.connection.resetAccumulated();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('รีเซ็ตค่าสะสมแล้ว')),
    );
  }

  Future<void> _openCalibration() async {
    final result = await showModalBottomSheet<CalibrationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CalibrationSheet(
        thresholds: _thresholds,
        calibration: widget.connection.calibration,
        currentCpm: widget.connection.latest?.cpm ?? 0,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _thresholds = result.thresholds);
    widget.connection.setCalibration(result.calibration);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.connection,
      builder: (context, _) {
        final connection = widget.connection;
        final latest = connection.latest;
        final doseRate = connection.doseRate;
        final level =
            latest == null ? HazardLevel.normal : _thresholds.levelFor(doseRate);
        final accent = AppTheme.colorFor(level);

        return Scaffold(
          appBar: AppBar(
            title: Text(connection.device?.name ?? 'Telepole'),
            actions: [
              IconButton(
                tooltip: _alarm.isMuted ? 'เปิดเสียงเตือน' : 'ปิดเสียงเตือน',
                icon: Icon(_alarm.isMuted ? Icons.volume_off : Icons.volume_up),
                onPressed: () => setState(() => _alarm.muted = !_alarm.isMuted),
              ),
              IconButton(
                tooltip: 'เกณฑ์เตือน & สอบเทียบ',
                icon: const Icon(Icons.tune),
                onPressed: _openCalibration,
              ),
            ],
          ),
          body: AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withOpacity(level == HazardLevel.normal ? 0.06 : 0.22),
                  AppTheme.bg,
                ],
                stops: const [0, 0.55],
              ),
            ),
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _StatusBanner(
                    level: level,
                    linkState: connection.state,
                    thresholds: _thresholds,
                    calibration: connection.calibration,
                  ),
                  const SizedBox(height: 16),
                  _CpmCard(cpm: latest?.cpm, accent: accent),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _MetricCard(
                          label: 'Dose Rate',
                          value: latest == null
                              ? '--'
                              : doseRate.toStringAsFixed(3),
                          unit: 'uSv / h  (ประมาณการ)',
                          icon: Icons.speed,
                          valueColor: accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          label: 'ปริมาณสะสม',
                          value: latest == null
                              ? '--'
                              : connection.accumulatedUSv.toStringAsFixed(3),
                          unit: 'uSv',
                          icon: Icons.hourglass_bottom,
                          action: TextButton.icon(
                            onPressed: latest == null ? null : _confirmReset,
                            icon: const Icon(Icons.restart_alt, size: 16),
                            label: const Text('Reset'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: const Size(0, 32),
                              foregroundColor: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _CalibrationNote(
                    calibration: connection.calibration,
                    onTap: _openCalibration,
                  ),
                  const SizedBox(height: 16),
                  _TrendPanel(
                    history: connection.history,
                    thresholds: _thresholds,
                    calibration: connection.calibration,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// แถบเตือนว่าค่า uSv/h เป็นค่าประมาณที่ขึ้นกับการสอบเทียบ
/// สำคัญมากสำหรับหัววัดที่ประกอบเอง เพราะไม่มีค่า sensitivity จาก datasheet
class _CalibrationNote extends StatelessWidget {
  final MeterCalibration calibration;
  final VoidCallback onTap;

  const _CalibrationNote({required this.calibration, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.outline),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 15, color: AppTheme.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'CPM คือค่าที่วัดได้จริง · uSv/h แปลงด้วยค่า '
                '${calibration.cpmPerUSvh.toStringAsFixed(1)} CPM ต่อ 1 uSv/h',
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  final List<Reading> history;
  final Thresholds thresholds;
  final MeterCalibration calibration;

  const _TrendPanel({
    required this.history,
    required this.thresholds,
    required this.calibration,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 10),
            child: Text(
              'แนวโน้ม CPM ย้อนหลัง',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ),
          Expanded(
            child: TrendChart(
              history: history,
              thresholds: thresholds,
              calibration: calibration,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final HazardLevel level;
  final LinkState linkState;
  final Thresholds thresholds;
  final MeterCalibration calibration;

  const _StatusBanner({
    required this.level,
    required this.linkState,
    required this.thresholds,
    required this.calibration,
  });

  @override
  Widget build(BuildContext context) {
    final connected = linkState == LinkState.connected;
    final color = connected ? AppTheme.colorFor(level) : AppTheme.textMuted;

    final String message;
    if (!connected) {
      message = 'การเชื่อมต่อขาด - ข้อมูลอาจไม่เป็นปัจจุบัน';
    } else if (level == HazardLevel.alarm) {
      final cpm = calibration.cpmFor(thresholds.alarm).toStringAsFixed(0);
      message = 'อันตราย - เกิน $cpm CPM ถอยห่างจากแหล่งกำเนิด';
    } else if (level == HazardLevel.elevated) {
      final cpm = calibration.cpmFor(thresholds.elevated).toStringAsFixed(0);
      message = 'เฝ้าระวัง - เกิน $cpm CPM';
    } else {
      message = 'ระดับรังสีปกติ';
    }

    final IconData icon;
    if (!connected) {
      icon = Icons.link_off;
    } else if (level == HazardLevel.alarm) {
      icon = Icons.warning_amber_rounded;
    } else {
      icon = Icons.verified_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ตัวเลขหลักของหน้าจอ: CPM ซึ่งเป็นค่าที่หลอด GM วัดได้จริง
class _CpmCard extends StatelessWidget {
  final double? cpm;
  final Color accent;

  const _CpmCard({required this.cpm, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(0.45), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.18),
            blurRadius: 28,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'COUNT RATE',
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            child: Text(
              cpm == null ? '---' : cpm!.toStringAsFixed(0),
              style: TextStyle(
                fontSize: 84,
                height: 1.05,
                fontWeight: FontWeight.w700,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'CPM  ·  counts per minute',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final Color? valueColor;
  final Widget? action;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    this.valueColor,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w600,
                color: valueColor ?? AppTheme.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Text(
            unit,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}
