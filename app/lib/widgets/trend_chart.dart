import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/reading.dart';
import '../theme.dart';

/// กราฟเส้นแนวโน้มแบบเรียลไทม์ — พล็อต CPS ไม่ใช่ CPM
///
/// เลือก CPS เพราะกราฟนี้มีไว้ "หาจุดร้อน" ไม่ใช่ "อ่านค่าที่แม่น"
/// CPM เป็นค่าเฉลี่ย 60 วินาที เอาหัววัดจ่อแหล่งรังสีแล้วกราฟจะไต่ขึ้นเป็นนาที
/// ส่วน CPS คือพัลส์ดิบของวินาทีนั้น ขยับตามทันทีที่ค่าเปลี่ยน
///
/// ราคาที่จ่ายคือกราฟหยึกหยัก เพราะการสลายตัวเป็นเหตุการณ์สุ่มแบบปัวซง
/// ที่รังสีพื้นหลังจะเห็นเด้ง 0-1-2 ตลอดเวลาโดยที่รังสีไม่ได้เปลี่ยน
/// ตัวเลข CPM ที่นิ่งกว่ายังแสดงเป็นตัวใหญ่อยู่ด้านบนของหน้าจอ
///
/// แกน X = วินาทีย้อนหลัง (0 คือค่าล่าสุด) · แกน Y = CPS
/// เส้นประคือเกณฑ์เตือน ซึ่งกำหนดเป็น uSv/h จึงต้องแปลงเป็น CPS ก่อนวาง
class TrendChart extends StatelessWidget {
  final List<Reading> history;
  final Thresholds thresholds;
  final MeterCalibration calibration;

  /// ยอดแกน Y ขั้นต่ำ กันไม่ให้กราฟดูโอเวอร์ตอนค่าต่ำ ๆ
  /// ที่รังสีพื้นหลัง CPS อยู่ราว 0-1 ถ้าปล่อยให้ scale ตามค่าจริง
  /// การเด้งจาก 0 เป็น 1 จะเต็มจอทั้งที่ไม่มีอะไรเกิดขึ้น
  static const double minTopCps = 4;

  const TrendChart({
    super.key,
    required this.history,
    required this.thresholds,
    required this.calibration,
  });

  /// firmware รุ่นเก่าส่งมาแค่ 3 ช่อง ไม่มี CPS — ประมาณจาก CPM แทน
  /// กราฟจะนิ่งเหมือนเดิม แต่ยังใช้งานได้ ไม่ใช่จอเปล่า
  static double _cpsOf(Reading r) => (r.cps ?? (r.cpm / 60.0)).toDouble();

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
      spots.add(FlSpot((i - last).toDouble(), _cpsOf(history[i])));
    }

    // เกณฑ์เตือนเก็บเป็น uSv/h -> แปลงเป็น CPM -> หาร 60 ได้ CPS
    final elevatedCps = calibration.cpmFor(thresholds.elevated) / 60.0;
    final alarmCps = calibration.cpmFor(thresholds.alarm) / 60.0;

    final peak = history.map(_cpsOf).reduce((a, b) => a > b ? a : b);
    // ให้เส้นเกณฑ์เตือนอยู่ในกรอบเสมอ เพื่ออ่านระยะห่างจากเกณฑ์ได้
    var top = (peak > alarmCps ? peak : alarmCps) * 1.25;
    if (top < minTopCps) top = minTopCps;

    // สีเส้นยังอิงระดับจาก CPM ที่เฉลี่ยแล้ว ไม่ใช่ CPS ดิบ
    // ไม่งั้นเส้นจะกะพริบเปลี่ยนสีทุกวินาทีตามความสุ่ม
    final level = thresholds.levelFor(calibration.doseRateFor(history.last.cpm));
    final lineColor = AppTheme.colorFor(level);

    return LineChart(
      LineChartData(
        minX: spots.first.x,
        maxX: 0,
        minY: 0,
        maxY: top,
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
              reservedSize: 34,
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
              y: elevatedCps,
              color: AppTheme.warn.withOpacity(0.7),
              strokeWidth: 1,
              dashArray: const [6, 4],
            ),
            HorizontalLine(
              y: alarmCps,
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
                    '${s.y.toStringAsFixed(0)} CPS\n'
                    '= ${(s.y * 60).toStringAsFixed(0)} CPM',
                    const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            // ไม่ทำเส้นโค้ง เพราะ CPS เป็นจำนวนเต็มที่กระโดด
            // การ smooth จะสร้างค่าที่ไม่เคยวัดได้จริงระหว่างจุด และอาจลากต่ำกว่าศูนย์
            isCurved: false,
            barWidth: 2,
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
      duration: const Duration(milliseconds: 150),
    );
  }
}
