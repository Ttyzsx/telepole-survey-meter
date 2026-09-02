import 'package:flutter/material.dart';

import '../models/survey_session.dart';
import '../services/session_recorder.dart';
import '../theme.dart';
import 'session_detail_screen.dart';

/// รายการการสำรวจที่บันทึกไว้ เรียงจากใหม่ไปเก่า
class SessionsScreen extends StatefulWidget {
  const SessionsScreen({super.key});

  @override
  State<SessionsScreen> createState() => _SessionsScreenState();
}

class _SessionsScreenState extends State<SessionsScreen> {
  late Future<List<SurveySession>> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = SessionRecorder.listSessions();
  }

  void _reload() {
    setState(() => _sessions = SessionRecorder.listSessions());
  }

  Future<void> _confirmDelete(SurveySession session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('ลบการสำรวจนี้?'),
        content: Text('${_formatDate(session.startedAt)} — ลบแล้วกู้คืนไม่ได้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SessionRecorder.delete(session);
    if (!mounted) return;
    _reload();
  }

  static String _formatDate(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)}/${t.year}  ${two(t.hour)}:${two(t.minute)}';
  }

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    if (minutes >= 60) return '${d.inHours} ชม. ${minutes % 60} นาที';
    if (minutes >= 1) return '$minutes นาที ${d.inSeconds % 60} วิ';
    return '${d.inSeconds} วินาที';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('บันทึกการสำรวจ'),
        actions: [
          IconButton(
            tooltip: 'โหลดใหม่',
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
          ),
        ],
      ),
      body: FutureBuilder<List<SurveySession>>(
        future: _sessions,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final sessions = snapshot.data ?? const <SurveySession>[];
          if (sessions.isEmpty) {
            return const _EmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final session = sessions[index];
              return _SessionTile(
                session: session,
                subtitle: '${_formatDuration(session.duration)} · '
                    '${session.sampleCount} จุด · '
                    'สูงสุด ${session.peakCpm.toStringAsFixed(0)} CPM',
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SessionDetailScreen(session: session),
                    ),
                  );
                  if (mounted) _reload();
                },
                onDelete: () => _confirmDelete(session),
              );
            },
          );
        },
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final SurveySession session;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.subtitle,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _SessionsScreenState._formatDate(session.startedAt),
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'ลบ',
                icon: const Icon(Icons.delete_outline,
                    color: AppTheme.textMuted, size: 20),
                onPressed: onDelete,
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timeline, size: 48, color: AppTheme.textMuted),
            SizedBox(height: 14),
            Text(
              'ยังไม่มีการสำรวจที่บันทึกไว้',
              style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'กดปุ่มวงกลมแดงบนหน้าหลักเพื่อเริ่มบันทึก\n'
              'ระหว่างบันทึกจะเขียนลงไฟล์ทันทีทุกวินาที',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
