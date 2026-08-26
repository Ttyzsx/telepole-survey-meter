import 'package:flutter/material.dart';

import '../models/reading.dart';
import '../theme.dart';

class CalibrationResult {
  final Thresholds thresholds;
  final MeterCalibration calibration;

  const CalibrationResult({required this.thresholds, required this.calibration});
}

/// แผงตั้งค่าเกณฑ์เตือน + สอบเทียบหลอด GM
///
/// สำหรับหัววัดที่ประกอบเอง ไม่มีค่า sensitivity จาก datasheet ให้ใช้
/// จึงมีโหมด "สอบเทียบภาคสนาม": วางหัววัดข้างเครื่องมาตรฐาน กรอกค่าที่เครื่องนั้นอ่านได้
/// แล้วแอปคำนวณ CPM ต่อ 1 uSv/h ให้เอง จาก CPM ที่กำลังวัดได้ในขณะนั้น
class CalibrationSheet extends StatefulWidget {
  final Thresholds thresholds;
  final MeterCalibration calibration;
  final double currentCpm;

  const CalibrationSheet({
    super.key,
    required this.thresholds,
    required this.calibration,
    required this.currentCpm,
  });

  @override
  State<CalibrationSheet> createState() => _CalibrationSheetState();
}

class _CalibrationSheetState extends State<CalibrationSheet> {
  late final TextEditingController _elevatedCtrl;
  late final TextEditingController _alarmCtrl;
  late final TextEditingController _sensitivityCtrl;
  final _referenceCtrl = TextEditingController();

  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    _elevatedCtrl =
        TextEditingController(text: widget.thresholds.elevated.toString());
    _alarmCtrl = TextEditingController(text: widget.thresholds.alarm.toString());
    _sensitivityCtrl = TextEditingController(
      text: widget.calibration.cpmPerUSvh.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _elevatedCtrl.dispose();
    _alarmCtrl.dispose();
    _sensitivityCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  /// คำนวณค่า sensitivity จากค่าอ้างอิงของเครื่องมาตรฐาน
  /// factor = CPM ที่วัดได้ตอนนี้ / ค่า uSv/h ของเครื่องมาตรฐาน
  void _computeFromReference() {
    final reference = double.tryParse(_referenceCtrl.text);
    if (reference == null || reference <= 0) {
      setState(() => _error = 'กรอกค่าอ้างอิงเป็นตัวเลขมากกว่า 0');
      return;
    }
    if (widget.currentCpm <= 0) {
      setState(() => _error = 'ยังไม่มีค่า CPM — รอให้เครื่องส่งข้อมูลก่อน');
      return;
    }
    final factor = widget.currentCpm / reference;
    setState(() {
      _sensitivityCtrl.text = factor.toStringAsFixed(1);
      _error = null;
      _info = 'ได้ค่า ${factor.toStringAsFixed(1)} CPM ต่อ 1 uSv/h '
          '(จาก ${widget.currentCpm.toStringAsFixed(0)} CPM)';
    });
  }

  void _save() {
    final elevated = double.tryParse(_elevatedCtrl.text);
    final alarm = double.tryParse(_alarmCtrl.text);
    final sensitivity = double.tryParse(_sensitivityCtrl.text);

    if (sensitivity == null || sensitivity <= 0) {
      setState(() => _error = 'ค่า sensitivity ต้องมากกว่า 0');
      return;
    }
    // เกณฑ์เตือนภัยต้องสูงกว่าเฝ้าระวังเสมอ ไม่งั้นสถานะจะสลับไปมาไม่สมเหตุผล
    if (elevated == null || alarm == null || elevated <= 0 || alarm <= elevated) {
      setState(() => _error = 'เกณฑ์เตือนภัยต้องมากกว่าเกณฑ์เฝ้าระวัง');
      return;
    }

    Navigator.pop(
      context,
      CalibrationResult(
        thresholds: Thresholds(elevated: elevated, alarm: alarm),
        calibration: MeterCalibration(cpmPerUSvh: sensitivity),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sensitivity =
        double.tryParse(_sensitivityCtrl.text) ?? widget.calibration.cpmPerUSvh;
    final elevated = double.tryParse(_elevatedCtrl.text) ?? 0;
    final alarm = double.tryParse(_alarmCtrl.text) ?? 0;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.outline,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'เกณฑ์เตือน',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      controller: _elevatedCtrl,
                      label: 'เฝ้าระวัง (uSv/h)',
                      helper: sensitivity > 0
                          ? '= ${(elevated * sensitivity).toStringAsFixed(0)} CPM'
                          : null,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      controller: _alarmCtrl,
                      label: 'เตือนภัย (uSv/h)',
                      helper: sensitivity > 0
                          ? '= ${(alarm * sensitivity).toStringAsFixed(0)} CPM'
                          : null,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'สอบเทียบหลอด GM',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'ค่านี้ใช้แปลง CPM เป็น uSv/h เท่านั้น — ไม่กระทบค่า CPM ที่วัดได้\n'
                'หลอดที่ประกอบเองไม่มีค่าจาก datasheet ควรสอบเทียบกับเครื่องมาตรฐาน',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              _NumberField(
                controller: _sensitivityCtrl,
                label: 'CPM ต่อ 1 uSv/h',
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MeterCalibration.presets.entries
                    .map(
                      (e) => ActionChip(
                        label: Text(
                          '${e.key}  ${e.value}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        backgroundColor: AppTheme.surfaceAlt,
                        side: const BorderSide(color: AppTheme.outline),
                        onPressed: () => setState(() {
                          _sensitivityCtrl.text = e.value.toStringAsFixed(1);
                          _info = 'ใช้ค่าจาก datasheet ของ ${e.key}';
                        }),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'สอบเทียบภาคสนาม',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'วางหัววัดข้างเครื่องมาตรฐานในสภาพเดียวกัน รอให้ค่านิ่ง '
                      'แล้วกรอกค่าที่เครื่องมาตรฐานอ่านได้\n'
                      'CPM ปัจจุบัน: ${widget.currentCpm.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _NumberField(
                            controller: _referenceCtrl,
                            label: 'ค่าอ้างอิง (uSv/h)',
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _computeFromReference,
                          child: const Text('คำนวณ'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_info != null) ...[
                const SizedBox(height: 12),
                Text(
                  _info!,
                  style: const TextStyle(color: AppTheme.safe, fontSize: 12),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(color: AppTheme.danger, fontSize: 12),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('ยกเลิก'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('บันทึก'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? helper;
  final ValueChanged<String>? onChanged;

  const _NumberField({
    required this.controller,
    required this.label,
    this.helper,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
