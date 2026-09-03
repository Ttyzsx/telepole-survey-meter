import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/reading.dart';
import '../theme.dart';

/// ค่าที่กราฟจะพล็อต — สลับได้จากปุ่มบนหัวการ์ด
///
/// ทั้งสองค่ามาจากพัลส์ชุดเดียวกัน ต่างกันแค่ช่วงเวลาที่เฉลี่ย
/// จึงเหมาะกับงานคนละแบบ ไม่มีอันไหนถูกกว่ากัน
enum TrendMetric {
  /// พัลส์ดิบของวินาทีที่เพิ่งผ่าน ไม่ผ่านการเฉลี่ย
  /// ขยับทันทีที่ค่าเปลี่ยน เหมาะกับการกวาดหาจุดร้อน แลกกับกราฟหยึกหยัก
  cps,

  /// ค่าเฉลี่ยจากหน้าต่างเลื่อน 60 วินาทีที่ firmware คำนวณมาให้
  /// นิ่งกว่ามาก เหมาะกับการอ่านค่า แลกกับการตอบสนองช้าถึงหนึ่งนาที
  cpm,
}

/// กราฟเส้นแนวโน้มแบบเรียลไทม์
///
/// แกน X = วินาทีย้อนหลัง (0 คือค่าล่าสุด) · แกน Y ขึ้นกับโหมดที่เลือก
/// เส้นประคือเกณฑ์เตือน ซึ่งกำหนดเป็น uSv/h จึงต้องแปลงให้ตรงหน่วยก่อนวาง
class TrendChart extends StatelessWidget {
  final List<Reading> history;
  final Thresholds thresholds;
  final MeterCalibration calibration;
  final TrendMetric metric;

  /// ยอดแกน Y ขั้นต่ำของแต่ละโหมด กันไม่ให้กราฟดูโอเวอร์ตอนค่าต่ำ ๆ
  /// ที่รังสีพื้นหลัง CPS อยู่ราว 0-1 ถ้าปล่อยให้ scale ตามค่าจริง
  /// การเด้งจาก 0 เป็น 1 จะเต็มจอทั้งที่ไม่มีอะไรเกิดขึ้น
  static const double _minTopCps = 4;
  static const double _minTopCpm = 40;

  const TrendChart({
    super.key,
    required this.history,
    required this.thresholds,
    required this.calibration,
    this.metric = TrendMetric.cps,
  });

  bool get _isCps => metric == TrendMetric.cps;

  /// firmware รุ่นเก่าส่งมาแค่ 3 ช่อง ไม่มี CPS — ประมาณจาก CPM แทน
  /// กราฟจะนิ่งเหมือนโหมด CPM แต่ยังใช้งานได้ ไม่ใช่จอเปล่า
  double _valueOf(Reading r) =>
      _isCps ? (r.cps ?? (r.cpm / 60.0)).toDouble() : r.cpm;

  /// เกณฑ์เตือนเก็บเป็น uSv/h แปลงเป็น CPM ก่อน แล้วหาร 60 ถ้าอยู่โหมด CPS
  double _thresholdFor(double doseRate) {
    final cpm = calibration.cpmFor(doseRate);
    return _isCps ? cpm / 60.0 : cpm;
  }

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
      spots.add(FlSpot((i - last).toDouble(), _valueOf(history[i])));
    }

    final elevatedLine = _thresholdFor(thresholds.elevated);
    final alarmLine = _thresholdFor(thresholds.alarm);

    final peak = history.map(_valueOf).reduce((a, b) => a > b ? a : b);
    // ให้เส้นเกณฑ์เตือนอยู่ในกรอบเสมอ เพื่ออ่านระยะห่างจากเกณฑ์ได้
    var top = (peak > alarmLine ? peak : alarmLine) * 1.25;
    final floor = _isCps ? _minTopCps : _minTopCpm;
    if (top < floor) top = floor;

    // สีเส้นอิงระดับจาก CPM ที่เฉลี่ยแล้วเสมอ แม้อยู่โหมด CPS
    // ไม่งั้นเส้นจะกะพริบเปลี่ยนสีทุกวินาทีตามความสุ่มของการนับ
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
              reservedSize: _isCps ? 34 : 42,
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
              y: elevatedLine,
              color: AppTheme.warn.withOpacity(0.7),
              strokeWidth: 1,
              dashArray: const [6, 4],
            ),
            HorizontalLine(
              y: alarmLine,
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
                    _isCps
                        ? '${s.y.toStringAsFixed(0)} CPS\n'
                            '= ${(s.y * 60).toStringAsFixed(0)} CPM'
                        : '${s.y.toStringAsFixed(0)} CPM\n'
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
            // โหมด CPS ไม่ทำเส้นโค้ง เพราะเป็นจำนวนเต็มที่กระโดด
            // การ smooth จะสร้างค่าที่ไม่เคยวัดได้จริงระหว่างจุด และอาจลากต่ำกว่าศูนย์
            // ส่วน CPM ผ่านการเฉลี่ยมาแล้ว เส้นโค้งเบา ๆ จึงไม่บิดเบือนอะไร
            isCurved: !_isCps,
            curveSmoothness: 0.2,
            barWidth: _isCps ? 2 : 2.5,
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
      duration: Duration(milliseconds: _isCps ? 150 : 250),
    );
  }
}
