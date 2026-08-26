import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/reading.dart';
import '../theme.dart';

/// กราฟเส้นแนวโน้ม CPM ย้อนหลัง
/// แกน X = วินาทีย้อนหลัง (0 คือค่าล่าสุด), แกน Y = CPM (ค่าดิบจากหลอด)
/// เส้นประคือเกณฑ์เตือน ซึ่งกำหนดเป็น uSv/h แล้วแปลงกลับมาเป็น CPM เพื่อวางบนแกนเดียวกัน
class TrendChart extends StatelessWidget {
  final List<Reading> history;
  final Thresholds thresholds;
  final MeterCalibration calibration;

  const TrendChart({
    super.key,
    required this.history,
    required this.thresholds,
    required this.calibration,
  });

  @override
  Widget build(BuildContext context) {
    if (history.length < 2) {
      return const Center(
        child: Text(
          'กำลังเก็บข้อมูล…',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    final spots = <FlSpot>[];
    final last = history.length - 1;
    for (var i = 0; i < history.length; i++) {
      spots.add(FlSpot((i - last).toDouble(), history[i].cpm));
    }

    final elevatedCpm = calibration.cpmFor(thresholds.elevated);
    final alarmCpm = calibration.cpmFor(thresholds.alarm);

    final peak = history.map((r) => r.cpm).reduce((a, b) => a > b ? a : b);
    // ให้เส้นเกณฑ์เตือนอยู่ในกรอบเสมอ เพื่ออ่านระยะห่างจากเกณฑ์ได้
    final maxY = (peak < alarmCpm ? alarmCpm : peak) * 1.25;
    final level = thresholds.levelFor(calibration.doseRateFor(history.last.cpm));
    final lineColor = AppTheme.colorFor(level);

    return LineChart(
      LineChartData(
        minX: spots.first.x,
        maxX: 0,
        minY: 0,
        maxY: maxY <= 0 ? 10 : maxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppTheme.outline.withOpacity(0.5),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              getTitlesWidget: (value, meta) => Text(
                value.toStringAsFixed(0),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: (spots.length / 4).ceilToDouble().clamp(1, 120),
              getTitlesWidget: (value, meta) => Text(
                value == 0 ? 'now' : '${value.toInt()}s',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: elevatedCpm,
              color: AppTheme.warn.withOpacity(0.7),
              strokeWidth: 1,
              dashArray: const [6, 4],
            ),
            HorizontalLine(
              y: alarmCpm,
              color: AppTheme.danger.withOpacity(0.8),
              strokeWidth: 1,
              dashArray: const [6, 4],
            ),
          ],
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched
                .map(
                  (s) => LineTooltipItem(
                    '${s.y.toStringAsFixed(0)} CPM\n'
                    '${calibration.doseRateFor(s.y).toStringAsFixed(3)} uSv/h',
                    const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            barWidth: 2.5,
            color: lineColor,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [lineColor.withOpacity(0.28), Colors.transparent],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 250),
    );
  }
}
