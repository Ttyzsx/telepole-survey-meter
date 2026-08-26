import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';

/// เสียงคลิกตามอัตรานับ (audible count) — เลียนแบบเสียงติ๊กของเครื่องสำรวจรังสี
///
/// ใช้ค่า CPS ที่ firmware ส่งมา ซึ่งเป็นจำนวนพัลส์ดิบของวินาทีที่ผ่านมา
/// จึงตอบสนองเร็วกว่าตัวเลข CPM บนจอที่เฉลี่ยมา 60 วินาที
///
/// ข้อจำกัดที่ยอมรับ: เสียงตามหลังเหตุการณ์จริงราว 1 วินาที เพราะแอปรู้เพียง
/// "วินาทีที่แล้วมีกี่พัลส์" ไม่ได้รู้เวลาของแต่ละพัลส์ ถ้าต้องการเสียงที่ตรงเป๊ะ
/// ต้องใช้บัซเซอร์ต่อกับ Arduino แทน — ปุ่มเปิด/ปิดจึงมีไว้เลือกอย่างใดอย่างหนึ่ง
class TickService {
  final AudioPlayer _player = AudioPlayer();
  final Random _random = Random();
  Timer? _timer;

  bool _enabled = true;
  bool _initialized = false;

  /// จำนวนคลิกที่ยังค้างรอเล่นในรอบวินาทีนี้
  int _pending = 0;

  /// แบ่งหนึ่งวินาทีเป็นช่วงย่อย แล้วสุ่มว่าช่วงไหนจะมีคลิก
  /// วิธีนี้ให้จังหวะกระจายแบบสุ่มเหมือนการสลายตัวจริง ด้วย timer เพียงตัวเดียว
  static const int _slotMs = 25;
  static const int _slotsPerSecond = 1000 ~/ _slotMs; // 40

  /// เพดานคลิกต่อวินาที — เกินกว่านี้หูแยกไม่ออกอยู่แล้ว และระบบเสียงจะเริ่มกระตุก
  static const int _maxTicksPerSecond = 30;

  bool get isEnabled => _enabled;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      // โหมด lowLatency ออกแบบมาสำหรับเสียงสั้นที่เล่นถี่ ๆ โดยเฉพาะ
      await _player.setPlayerMode(PlayerMode.lowLatency);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(AssetSource('tick.wav'));
    } on Exception {
      // เล่นเสียงไม่ได้ไม่ควรทำให้หน้าจอล้ม — ตัวเลขยังต้องอ่านได้ตามปกติ
    }
    _timer = Timer.periodic(
      const Duration(milliseconds: _slotMs),
      (_) => _onSlot(),
    );
  }

  set enabled(bool value) {
    _enabled = value;
    if (!value) _pending = 0;
  }

  /// รับจำนวนพัลส์ของวินาทีล่าสุด แล้วทยอยเล่นคลิกให้ครบภายในวินาทีถัดไป
  void submit(int? cps) {
    if (!_enabled || cps == null || cps <= 0) {
      _pending = 0;
      return;
    }
    // ไม่สะสมของค้างจากรอบก่อน ไม่งั้นเสียงจะรัวตามหลังไปเรื่อย ๆ เมื่อค่าพุ่ง
    _pending = cps > _maxTicksPerSecond ? _maxTicksPerSecond : cps;
  }

  void _onSlot() {
    if (!_enabled || _pending <= 0) return;

    // โอกาสที่ช่วงนี้จะมีคลิก = จำนวนที่เหลือ ÷ จำนวนช่วงที่เหลือ
    // ทำให้คลิกกระจายทั่วทั้งวินาทีโดยไม่ต้องคำนวณตารางเวลาล่วงหน้า
    if (_random.nextInt(_slotsPerSecond) >= _pending) return;

    _pending--;
    _play();
  }

  void _play() {
    // ในโหมด lowLatency ต้องกรอกลับไปต้นไฟล์เองก่อนเล่นซ้ำ
    _player.seek(Duration.zero).then((_) => _player.resume()).catchError((_) {});
  }

  void dispose() {
    _timer?.cancel();
    _player.dispose();
  }
}
