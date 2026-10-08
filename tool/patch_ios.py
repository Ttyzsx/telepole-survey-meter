#!/usr/bin/env python3
"""เติมค่าที่จำเป็นลงใน Info.plist ที่ `flutter create` สร้างขึ้น

ทำงานแบบ idempotent — รันซ้ำได้ ค่าเดิมถูกเขียนทับด้วยค่าเดียวกัน
เรียกใช้จากโฟลเดอร์ app/ :  python3 ../tool/patch_ios.py
"""

import plistlib
import sys
from pathlib import Path

INFO_PLIST = Path("ios/Runner/Info.plist")

BLUETOOTH_REASON = "ใช้เชื่อมต่อกับหัววัดรังสี Telepole เพื่อรับค่าที่วัดได้"

SETTINGS = {
    "CFBundleDisplayName": "Telepole",
    # iOS ปิดแอปทันทีที่แตะ Bluetooth ถ้าไม่มีข้อความนี้ — ไม่ใช่แค่ขอสิทธิ์ไม่ผ่าน
    "NSBluetoothAlwaysUsageDescription": BLUETOOTH_REASON,
    # คีย์รุ่นเก่า (iOS 12 ลงไป) ใส่ไว้ให้เครื่องเก่ายังเปิดแอปได้
    "NSBluetoothPeripheralUsageDescription": BLUETOOTH_REASON,
    # ให้โฟลเดอร์ Documents ของแอปโผล่ในแอป Files และ Finder/iTunes
    # ไฟล์ CSV ของการสำรวจจึงลากออกมาได้ เหมือน external app dir บน Android
    "UIFileSharingEnabled": True,
    "LSSupportsOpeningDocumentsInPlace": True,
    # แอปไม่ได้เข้ารหัสอะไรเอง — ตอบไว้เลยจะได้ไม่ถูกถามตอนอัปขึ้น TestFlight
    "ITSAppUsesNonExemptEncryption": False,
}


def main() -> int:
    if not INFO_PLIST.exists():
        print(f"[patch_ios] ไม่พบ {INFO_PLIST} — รัน flutter create ก่อน", file=sys.stderr)
        return 1

    with INFO_PLIST.open("rb") as handle:
        info = plistlib.load(handle)

    patched = {**info, **SETTINGS}

    with INFO_PLIST.open("wb") as handle:
        plistlib.dump(patched, handle)

    print(f"[patch_ios] ตั้งค่า {len(SETTINGS)} คีย์ใน {INFO_PLIST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
