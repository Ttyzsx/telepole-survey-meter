import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/reading.dart';
import '../services/alarm_service.dart';
import '../services/session_recorder.dart';
import '../services/telepole_connection.dart';
import '../services/tick_service.dart';
import '../theme.dart';
import '../widgets/calibration_sheet.dart';
import '../widgets/trend_chart.dart';
import 'sessions_screen.dart';

class DashboardScreen extends StatefulWidget {
  final TelepoleConnection connection;

  const DashboardScreen({super.key, required this.connection});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _alarm = AlarmService();
  final _tick = TickService();
  final _recorder = SessionRecorder();
  Thresholds _thresholds = const Thresholds();
  TrendMetric _trendMetric = TrendMetric.cps;

  @override
  void initState() {
    super.initState();
    _alarm.init();
    _tick.init();
    widget.connection.addListener(_onReading);
    _recorder.addListener(_onRecorderChanged);
  }

  @override
  void dispose() {
    widget.connection.removeListener(_onReading);
    _recorder.removeListener(_onRecorderChanged);
    _recorder.dispose();
    _alarm.dispose();
    _tick.dispose();
    super.dispose();
  }

  void _onReading() {
    final latest = widget.connection.latest;
    if (latest == null) return;
    _alarm.update(_thresholds.levelFor(widget.connection.doseRate));
    _tick.submit(latest.cps);
    _recorder.add(
      latest,
      doseRate: widget.connection.doseRate,
      accumulatedUSv: widget.connection.accumulatedUSv,
    );
  }

  void _onRecorderChanged() {
    if (mounted) setState(() {});
  }

  /// สลับสถานะบันทึก - ตอนหยุดจะสรุปให้ทันทีว่าได้อะไรไปบ้าง
  /// เพราะภาคสนามต้องรู้เดี๋ยวนั้นว่าเก็บข้อมูลสำเร็จไหม จะได้ไม่ต้องเดินกลับไปวัดใหม่
  Future<void> _toggleRecording() async {
    final messenger = ScaffoldMessenger.of(context);

    if (_recorder.isRecording) {
      final session = await _recorder.stop();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            session == null
                ? 'ไม่มีข้อมูลถูกบันทึก'
                : 'บันทึกแล้ว ${session.sampleCount} จุด - '
                    'สูงสุด ${session.peakCpm.toStringAsFixed(0)} CPM',
          ),
          action: session == null
              ? null
              : SnackBarAction(label: 'เปิดดู', onPressed: _openSessions),
        ),
      );
      return;
    }

    final started =
        await _recorder.start(calibration: widget.connection.calibration);
    if (!mounted) return;
    if (!started) {
      messenger.showSnackBar(
        SnackBar(content: Text(_recorder.error ?? 'เริ่มบันทึกไม่สำเร็จ')),
      );
    }
  }

  Future<void> _openSessions() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SessionsScreen()),
    );
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
                tooltip: _tick.isEnabled
                    ? 'ปิดเสียงคลิกตามอัตรานับ'
                    : 'เปิดเสียงคลิกตามอัตรานับ',
                icon: Icon(
                  Icons.graphic_eq,
                  color: _tick.isEnabled ? AppTheme.safe : AppTheme.textMuted,
                ),
                onPressed: () =>
                    setState(() => _tick.enabled = !_tick.isEnabled),
              ),
              IconButton(
                tooltip: _alarm.isMuted ? 'เปิดเสียงเตือน' : 'ปิดเสียงเตือน',
                icon: Icon(_alarm.isMuted ? Icons.volume_off : Icons.volume_up),
                onPressed: () => setState(() => _alarm.muted = !_alarm.isMuted),
              ),
              IconButton(
                tooltip: _recorder.isRecording
                    ? 'หยุดบันทึกการสำรวจ'
                    : 'เริ่มบันทึกการสำรวจ',
                icon: Icon(
                  _recorder.isRecording
                      ? Icons.stop_circle
                      : Icons.fiber_manual_record,
                  color: _recorder.isRecording
                      ? AppTheme.danger
                      : AppTheme.textMuted,
                ),
                onPressed: latest == null ? null : _toggleRecording,
              ),
              IconButton(
                tooltip: 'บันทึกการสำรวจที่ผ่านมา',
                icon: const Icon(Icons.history),
                onPressed: _openSessions,
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
                  if (_recorder.isRecording) ...[
                    const SizedBox(height: 12),
                    _RecordingBar(
                      elapsed: _recorder.elapsed,
                      sampleCount: _recorder.sampleCount,
                      peakCpm: _recorder.peakCpm,
                      onStop: _toggleRecording,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _CpmCard(cpm: latest?.cpm, cps: latest?.cps, accent: accent),
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
                  if (connection.isDemo) ...[
                    const SizedBox(height: 12),
                    _DemoPanel(
                      baseCpm: connection.demoBaseCpm,
                      onChanged: connection.setDemoBaseCpm,
                    ),
                  ],
                  const SizedBox(height: 16),
                  _TrendPanel(
                    history: connection.history,
                    thresholds: _thresholds,
                    calibration: connection.calibration,
                    metric: _trendMetric,
                    onMetricChanged: (m) => setState(() => _trendMetric = m),
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
/// ค่า datasheet ของ LND 712 ใช้เป็นค่าเริ่มต้นได้ แต่ยังไม่ใช่ค่าที่สอบเทียบแล้ว
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

/// แถบควบคุมโหมดสาธิต — เลื่อนเพื่อจำลองว่าเข้าใกล้แหล่งกำเนิดรังสี
class _DemoPanel extends StatelessWidget {
  final double baseCpm;
  final ValueChanged<double> onChanged;

  const _DemoPanel({required this.baseCpm, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
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
              const Icon(Icons.science_outlined,
                  size: 15, color: AppTheme.warn),
              const SizedBox(width: 6),
              const Text(
                'โหมดสาธิต',
                style: TextStyle(
                  color: AppTheme.warn,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'ตั้งไว้ ${baseCpm.toStringAsFixed(0)} CPM',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
          const Text(
            'ข้อมูลจำลอง ไม่ใช่ค่าที่วัดได้จริง — เลื่อนเพื่อทดสอบระบบเตือน',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10, height: 1.5),
          ),
          Slider(
            value: baseCpm.clamp(0, 800),
            min: 0,
            max: 800,
            divisions: 80,
            activeColor: AppTheme.warn,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _TrendPanel extends StatelessWidget {
  final List<Reading> history;
  final Thresholds thresholds;
  final MeterCalibration calibration;
  final TrendMetric metric;
  final ValueChanged<TrendMetric> onMetricChanged;

  const _TrendPanel({
    required this.history,
    required this.thresholds,
    required this.calibration,
    required this.metric,
    required this.onMetricChanged,
  });

  static const _labels = {
    TrendMetric.cps: 'พัลส์ดิบรายวินาที ตอบสนองทันที',
    TrendMetric.cpm: 'ค่าเฉลี่ย 60 วินาที นิ่งแต่ตามช้า',
  };

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
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 10, right: 2),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _labels[metric]!,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 12),
                  ),
                ),
                _MetricToggle(metric: metric, onChanged: onMetricChanged),
              ],
            ),
          ),
          Expanded(
            child: TrendChart(
              history: history,
              thresholds: thresholds,
              calibration: calibration,
              metric: metric,
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
  final int? cps;
  final Color accent;

  const _CpmCard({required this.cpm, required this.cps, required this.accent});

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
            'CPM  ·  เฉลี่ย 60 วินาที',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
          // CPS เป็นค่าดิบของวินาทีล่าสุด ตอบสนองทันทีตอนกวาดหาจุดร้อน
          // ต่างจาก CPM ด้านบนที่เฉลี่ยมาแล้วจึงขยับช้า
          if (cps != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.outline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$cps',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: accent,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'CPS  ·  วินาทีล่าสุด',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
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

/// แถบสถานะระหว่างบันทึก - ต้องเห็นชัดว่ากำลังบันทึกอยู่
/// เพราะการเผลอปล่อยให้บันทึกค้างไว้ทั้งวันทำให้ไฟล์บวมและหาช่วงที่ต้องการไม่เจอ
class _RecordingBar extends StatelessWidget {
  final Duration elapsed;
  final int sampleCount;
  final double peakCpm;
  final VoidCallback onStop;

  const _RecordingBar({
    required this.elapsed,
    required this.sampleCount,
    required this.peakCpm,
    required this.onStop,
  });

  String get _elapsedLabel {
    String two(int v) => v.toString().padLeft(2, '0');
    final minutes = elapsed.inMinutes;
    if (minutes >= 60) {
      return '${elapsed.inHours}:${two(minutes % 60)}:'
          '${two(elapsed.inSeconds % 60)}';
    }
    return '${two(minutes)}:${two(elapsed.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppTheme.danger.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.danger.withOpacity(0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.fiber_manual_record,
              color: AppTheme.danger, size: 14),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'กำลังบันทึก  $_elapsedLabel',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$sampleCount จุด - สูงสุด ${peakCpm.toStringAsFixed(0)} CPM',
                  style:
                      const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onStop,
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('หยุด'),
          ),
        ],
      ),
    );
  }
}

/// ปุ่มสลับค่าที่กราฟพล็อต — CPS ดิบ หรือ CPM เฉลี่ย
///
/// ทำเป็นปุ่มคู่ติดกันแทน dropdown เพราะมีแค่สองตัวเลือก
/// กดครั้งเดียวถึงปลายทาง ไม่ต้องเปิดเมนูแล้วเลือก
class _MetricToggle extends StatelessWidget {
  final TrendMetric metric;
  final ValueChanged<TrendMetric> onChanged;

  const _MetricToggle({required this.metric, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg('CPS', TrendMetric.cps),
          _seg('CPM', TrendMetric.cpm),
        ],
      ),
    );
  }

  Widget _seg(String label, TrendMetric value) {
    final selected = metric == value;
    return GestureDetector(
      onTap: selected ? null : () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppTheme.safe : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppTheme.bg : AppTheme.textMuted,
          ),
        ),
      ),
    );
  }
}
