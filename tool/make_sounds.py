#!/usr/bin/env python3
"""สังเคราะห์ไฟล์เสียงของแอป: app/assets/alarm.wav และ tick.wav

เสียงเตือนเป็น "หวอกวาดความถี่" (sweep/warble) 900 -> 2400 Hz สองรอบติดกัน
เลือกแบบนี้เพราะบี๊บความถี่เดียวซ้ำ ๆ ฟังแล้วเหมือนนาฬิกาปลุกมือถือ
ซึ่งคนมักเผลอปิดทิ้งโดยไม่คิด ส่วนเสียงกวาดความถี่เป็นสัญญาณเตือนภัย
ที่หูแยกออกทันทีว่าไม่ใช่เสียงแจ้งเตือนทั่วไป และตัดผ่านเสียงรบกวนได้ดีกว่า
เพราะพลังงานกระจายอยู่หลายความถี่ ไม่ตกหลุมความถี่ที่ห้องนั้นดูดกลืนพอดี

AlarmService เป็นคนคุมจังหวะการเล่นซ้ำเอง (ทุก 0.7 วิ ตอนเตือนภัย)
ไฟล์นี้จึงเก็บแค่ชุดเดียว ไม่ต้องวนลูปในตัวไฟล์

รัน:  python tool/make_sounds.py
"""

import math
import random
import struct
import wave
from pathlib import Path

SAMPLE_RATE = 44100

# เสียงเตือน: กวาดความถี่จากต่ำขึ้นสูง ทำซ้ำเป็นชุด
SWEEP_START_HZ = 900.0
SWEEP_END_HZ = 2400.0
SWEEP_MS = 170
SWEEP_COUNT = 2
GAP_MS = 40
HARMONIC_MIX = 0.28  # ผสมฮาร์โมนิกที่สาม ให้เสียงมีความ "บาด" แบบไซเรน ไม่นุ่มแบบไซน์เปล่า
FADE_MS = 5  # กันเสียง "แคร็ก" ตอนคลื่นตัดกลางคัน
AMPLITUDE = 0.85

ASSETS = Path(__file__).resolve().parent.parent / "app" / "assets"

# เสียงคลิกตามอัตรานับ — สั้นมากเพราะอาจดังหลายครั้งต่อวินาที
TICK_MS = 9
TICK_AMPLITUDE = 0.55
TICK_DECAY = 260.0  # ยิ่งมากยิ่งดับเร็ว ทำให้ฟังเป็น "คลิก" ไม่ใช่ "ปี๊บ"


def sweep_samples() -> list[float]:
    """หนึ่งรอบของการกวาดความถี่ พร้อม fade in/out กันเสียงแตก

    ต้องสะสมเฟส (phase) ทีละแซมเปิลแทนการใส่ความถี่ลงในสูตร sin ตรง ๆ
    เพราะถ้าความถี่เปลี่ยนแต่คูณกับเวลาที่เดินไปเรื่อย ๆ เฟสจะกระโดด
    ได้ยินเป็นเสียงแตกเป็นช่วง ๆ แทนที่จะเป็นการกวาดที่ลื่นไหล
    """
    total = int(SAMPLE_RATE * SWEEP_MS / 1000)
    fade = int(SAMPLE_RATE * FADE_MS / 1000)
    out = []
    phase = 0.0
    for i in range(total):
        progress = i / total
        frequency = SWEEP_START_HZ + (SWEEP_END_HZ - SWEEP_START_HZ) * progress
        phase += 2 * math.pi * frequency / SAMPLE_RATE
        value = math.sin(phase) + HARMONIC_MIX * math.sin(3 * phase)
        value /= 1 + HARMONIC_MIX  # ปรับกลับให้ยอดคลื่นไม่เกิน 1 หลังผสมฮาร์โมนิก
        # ค่อย ๆ ดังขึ้นตอนต้นและเบาลงตอนท้าย
        if i < fade:
            value *= i / fade
        elif i > total - fade:
            value *= (total - i) / fade
        out.append(value * AMPLITUDE)
    return out


def silence_samples(duration_ms: int) -> list[float]:
    return [0.0] * int(SAMPLE_RATE * duration_ms / 1000)


def tick_samples() -> list[float]:
    """เสียงคลิกแบบเครื่องนับไกเกอร์

    ใช้สัญญาณรบกวน (noise) ที่ดับเร็วมาก แทนที่จะเป็นคลื่นไซน์
    เพราะคลื่นไซน์สั้น ๆ ยังฟังเป็น "ปี๊บ" อยู่ ส่วน noise ที่ดับเร็วให้เสียง "แคะ"
    ซึ่งใกล้เคียงเสียงเครื่องจริงที่มาจากการกระตุกลำโพงทีเดียว
    """
    rng = random.Random(1)  # ตรึง seed ให้ไฟล์ที่ได้เหมือนเดิมทุกครั้งที่รัน
    total = int(SAMPLE_RATE * TICK_MS / 1000)
    out = []
    for i in range(total):
        envelope = math.exp(-TICK_DECAY * i / SAMPLE_RATE)
        out.append(rng.uniform(-1.0, 1.0) * envelope * TICK_AMPLITUDE)
    return out


def write_wav(name: str, samples: list[float]) -> None:
    path = ASSETS / name
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)  # 16-bit
        f.setframerate(SAMPLE_RATE)
        f.writeframes(
            b"".join(
                struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples
            )
        )
    duration = len(samples) / SAMPLE_RATE
    # ข้อความ ASCII ล้วน เพราะบาง console (เช่น cp932) พิมพ์ไทยไม่ได้แล้ว crash
    print(f"wrote {path} ({path.stat().st_size} bytes, {duration:.3f}s)")


def main() -> None:
    alarm = []
    for index in range(SWEEP_COUNT):
        if index > 0:
            alarm += silence_samples(GAP_MS)
        alarm += sweep_samples()
    write_wav("alarm.wav", alarm)
    write_wav("tick.wav", tick_samples())


if __name__ == "__main__":
    main()
