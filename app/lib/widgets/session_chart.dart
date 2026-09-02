import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/survey_session.dart';
import '../theme.dart';

/// กราฟ CPM ของการสำรวจทั้งครั้ง (ต่างจากกราฟ TrendChart บนหน้าหลัก ที่แสดงแค่ 5 นาทีล่าสุด)
///
/// แกน X เป็นเวลาที่ผ่านไปตั้งแต่เริ่มบันทึก แสดงเป็น mm:ss
/// การสำรวจยาว ๆ มีจุดหลายพันจุด เกินที่จอมือถือจะแสดงได้จริง จึงต้องย่อจำนวนจุดก่อนวาด
class SessionChart extends StatelessWidget {
  final SurveySession session;

  /// จำนวนจุดสูงสุดที่ยอมวาด — มากกว่านี้กราฟไม่ได้ละเอียดขึ้นในสายตา แต่เริ่มกระตุก
  static const int maxPoints = 480;

  const SessionChart({super.key, required this.session});

  /// ย่อข้อมูลด้วยการแบ่งเป็นถัง แล้วเก็บ "ค่าสูงสุด" ของแต่ละถัง
  ///
  /// จงใจไม่ใช้ค่าเฉลี่ย เพราะจุดที่เจอรังสีสูงมักเป็นยอดแหลมสั้น ๆ ตอนกวาดหัววัดผ่าน
  /// ถ้าเฉลี่ยจะกลบยอดนั้นหายไป ซึ่งเป็นสิ่งเดียวที่คนดูกราฟสำรวจอยากเห็น
  static List<FlSpot> downsample(List<SurveySample> samples) {
    if (samples.length <= maxPoints) {
      return [
        for (final s in samples) FlSpot(s.elapsedSeconds, s.cpm),
      ];
    }

    final bucketSize = (samples.length / maxPoints).ceil();
    final spots = <FlSpot>[];
    for (var start = 0; start < samples.length; start += bucketSize) {
      final end = (start + bucketSize).clamp(0, samples.length);
      var peak = samples[start];
      for (var i = start; i < end; i++) {
        if (samples[i].cpm > peak.cpm) peak = samples[i];
      }
      spots.add(FlSpot(peak.elapsedSeconds, peak.cpm));
    }
    return spots;
  }

  static String formatElapsed(double seconds) {
    final total = seconds.round();
    final minutes = total ~/ 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      return '${hours}h${(minutes % 60).toString().padLeft(2, '0')}';
    }
    return '$minutes:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (session.samples.length < 2) {
      return const Center(
        child: Text(
          'ข้อมูลน้อยเกินกว่าจะวาดกราฟ',
          style: TextStyle(color: AppTheme.textMuted),
        ),
      );
    }

    final spots = downsample(session.samples);
    final peak = session.peakCpm;
    final maxX = spots.last.x <= 0 ? 1.0 : spots.last.x;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxX,
        minY: 0,
        maxY: peak <= 0 ? 10 : peak * 1.2,
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
              reservedSize: 44,
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
              interval: maxX / 4,
              getTitlesWidget: (value, meta) => Text(
                formatElapsed(value),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
              ),
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touched) => touched
                .map(
                  (s) => LineTooltipItem(
                    '${s.y.toStringAsFixed(0)} CPM\n'
                    'ที่นาทีที่ ${formatElapsed(s.x)}',
                    const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
                  ),
                )
                .toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false, // ข้อมูลสำรวจต้องอ่านยอดจริง ไม่ใช่เส้นที่ถูกทำให้สวย
            barWidth: 2,
            color: AppTheme.safe,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.safe.withOpacity(0.25),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
