#!/usr/bin/env python3
"""สังเคราะห์ไฟล์เสียงเตือน app/assets/alarm.wav

เสียงเป็นบี๊บคู่สั้น ๆ ความถี่ 2700 Hz ซึ่งเป็นย่านที่ลำโพงมือถือดังที่สุด
และหูคนไวที่สุด — เลือกเพื่อให้ได้ยินในที่ที่มีเสียงรบกวน

AlarmService เป็นคนคุมจังหวะการเล่นซ้ำเอง (ทุก 0.7 วิ ตอนเตือนภัย)
ไฟล์นี้จึงเก็บแค่บี๊บชุดเดียว ไม่ต้องวนลูปในตัวไฟล์

รัน:  python tool/make_alarm_wav.py
"""

import math
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100
FREQUENCY = 2700.0
BEEP_MS = 90
GAP_MS = 60
FADE_MS = 5  # กันเสียง "แคร็ก" ตอนคลื่นตัดกลางคัน
AMPLITUDE = 0.85

OUTPUT = Path(__file__).resolve().parent.parent / "app" / "assets" / "alarm.wav"


def beep_samples() -> list[float]:
    """หนึ่งบี๊บ พร้อม fade in/out กันเสียงแตก"""
    total = int(SAMPLE_RATE * BEEP_MS / 1000)
    fade = int(SAMPLE_RATE * FADE_MS / 1000)
    out = []
    for i in range(total):
        value = math.sin(2 * math.pi * FREQUENCY * i / SAMPLE_RATE)
        # ค่อย ๆ ดังขึ้นตอนต้นและเบาลงตอนท้าย
        if i < fade:
            value *= i / fade
        elif i > total - fade:
            value *= (total - i) / fade
        out.append(value * AMPLITUDE)
    return out


def silence_samples(duration_ms: int) -> list[float]:
    return [0.0] * int(SAMPLE_RATE * duration_ms / 1000)


def main() -> None:
    samples = beep_samples() + silence_samples(GAP_MS) + beep_samples()

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)  # 16-bit
        f.setframerate(SAMPLE_RATE)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
        )
        f.writeframes(frames)

    duration = len(samples) / SAMPLE_RATE
    # ข้อความ ASCII ล้วน เพราะบาง console (เช่น cp932) พิมพ์ไทยไม่ได้แล้ว crash
    print(f"wrote {OUTPUT} ({OUTPUT.stat().st_size} bytes, {duration:.3f}s)")


if __name__ == "__main__":
    main()
