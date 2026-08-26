#!/usr/bin/env python3
"""แทรก permission ที่จำเป็นลงใน AndroidManifest.xml ที่ `flutter create` สร้างขึ้น

ทำงานแบบ idempotent — รันซ้ำได้โดยไม่แทรกซ้ำ
เรียกใช้จากโฟลเดอร์ app/ :  python3 ../tool/patch_android.py
"""

import re
import sys
from pathlib import Path

MANIFEST = Path("android/app/src/main/AndroidManifest.xml")

PERMISSIONS = """
    <!-- Android 11 (API 30) และต่ำกว่า -->
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="28" />

    <!-- Android 12 (API 31) ขึ้นไป -->
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
        android:usesPermissionFlags="neverForLocation" tools:targetApi="s" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />

    <uses-permission android:name="android.permission.VIBRATE" />

    <uses-feature android:name="android.hardware.bluetooth" android:required="false" />

"""

TOOLS_NS = 'xmlns:tools="http://schemas.android.com/tools"'


def main() -> int:
    if not MANIFEST.exists():
        print(f"[patch_android] ไม่พบ {MANIFEST} — รัน flutter create ก่อน", file=sys.stderr)
        return 1

    source = MANIFEST.read_text(encoding="utf-8")

    if "BLUETOOTH_CONNECT" in source:
        print("[patch_android] แพตช์ไว้แล้ว ข้าม")
        return 0

    # เพิ่ม xmlns:tools ให้แท็ก <manifest> เพราะ tools:targetApi ต้องใช้
    if TOOLS_NS not in source:
        source = re.sub(
            r"(<manifest\b[^>]*?)(>)",
            lambda m: f"{m.group(1)}\n    {TOOLS_NS}{m.group(2)}",
            source,
            count=1,
        )

    # แทรก permission ก่อนแท็ก <application>
    marker = source.find("<application")
    if marker == -1:
        print("[patch_android] ไม่พบแท็ก <application>", file=sys.stderr)
        return 1

    # ย้อนไปต้นบรรทัดของ <application> เพื่อไม่ให้ indent เพี้ยน
    line_start = source.rfind("\n", 0, marker) + 1
    patched = source[:line_start] + PERMISSIONS.lstrip("\n") + source[line_start:]

    MANIFEST.write_text(patched, encoding="utf-8")
    print("[patch_android] แทรก permission เรียบร้อย")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
