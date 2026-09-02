import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/survey_session.dart';
import '../theme.dart';
import '../widgets/session_chart.dart';

/// กราฟและสรุปของการสำรวจหนึ่งครั้ง พร้อมส่งออกไฟล์ CSV
class SessionDetailScreen extends StatelessWidget {
  final SurveySession session;

  const SessionDetailScreen({super.key, required this.session});

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Share.shareXFiles(
        [XFile(session.path, mimeType: 'text/csv')],
        subject: 'Telepole survey ${session.id}',
      );
    } on Object catch (e) {
      // เครื่องที่ไม่มีแอปรับไฟล์เลยจะโยน exception — บอกที่อยู่ไฟล์ไว้ให้ไปหยิบเองได้
      messenger.showSnackBar(
        SnackBar(
          content: Text('ส่งออกไม่สำเร็จ ($e)\nไฟล์อยู่ที่ ${session.path}'),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = session.duration;

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายละเอียดการสำรวจ'),
        actions: [
          IconButton(
            tooltip: 'ส่งออกไฟล์ CSV',
            icon: const Icon(Icons.ios_share),
            onPressed: () => _export(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Text(
            session.id,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
          if (session.note != null) ...[
            const SizedBox(height: 6),
            Text(
              session.note!,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            ),
          ],
          const SizedBox(height: 14),
          Container(
            height: 260,
            padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
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
                    'CPM ตลอดการสำรวจ',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                  ),
                ),
                Expanded(child: SessionChart(session: session)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SummaryGrid(session: session, duration: duration),
          const SizedBox(height: 14),
          const _CalibrationFootnote(),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final SurveySession session;
  final Duration duration;

  const _SummaryGrid({required this.session, required this.duration});

  @override
  Widget build(BuildContext context) {
    final items = <(String, String)>[
      ('ระยะเวลา', _formatDuration(duration)),
      ('จำนวนจุดที่บันทึก', '${session.sampleCount}'),
      ('CPM สูงสุด', session.peakCpm.toStringAsFixed(0)),
      ('CPM เฉลี่ย', session.meanCpm.toStringAsFixed(1)),
      ('ปริมาณสะสมช่วงนี้', '${session.totalUSv.toStringAsFixed(3)} uSv'),
      ('ค่าสอบเทียบที่ใช้', '${session.cpmPerUSvh.toStringAsFixed(1)} CPM/uSv·h'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.outline),
      ),
      child: Column(
        children: [
          for (final (label, value) in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 13),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    if (minutes >= 60) return '${d.inHours} ชม. ${minutes % 60} นาที';
    if (minutes >= 1) return '$minutes นาที ${d.inSeconds % 60} วิ';
    return '${d.inSeconds} วินาที';
  }
}

class _CalibrationFootnote extends StatelessWidget {
  const _CalibrationFootnote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        'ค่า uSv/h ในไฟล์คำนวณด้วยค่าสอบเทียบ ณ ตอนที่บันทึก '
        'ถ้าเปลี่ยนค่าสอบเทียบภายหลัง ตัวเลขในไฟล์เก่าจะไม่เปลี่ยนตาม '
        'คอลัมน์ CPM ในไฟล์เป็นค่าดิบ จึงคำนวณใหม่ได้เสมอ',
        style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.5),
      ),
    );
  }
}
