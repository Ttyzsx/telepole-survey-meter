#!/usr/bin/env python3
"""แทรก permission ที่จำเป็นลงใน AndroidManifest.xml ที่ `flutter create` สร้างขึ้น

ทำงานแบบ idempotent — รันซ้ำได้โดยไม่แทรกซ้ำ
เรียกใช้จากโฟลเดอร์ app/ :  python3 ../tool/patch_android.py
"""

import re
import sys
from pathlib import Path

MANIFEST = Path("android/app/src/main/AndroidManifest.xml")

# compileSdk ที่ปลั๊กอินต้องการสูงสุด ณ ตอนนี้คือ 37 (permission_handler 13)
# template ของ flutter ใช้ค่า flutter.compileSdkVersion ซึ่งตามไม่ทัน จึงตั้งตายตัว
COMPILE_SDK = 37
GRADLE_FILES = [
    Path("android/app/build.gradle.kts"),
    Path("android/app/build.gradle"),
]

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


def patch_compile_sdk() -> None:
    """บังคับ compileSdk ในโมดูล app ให้สูงพอสำหรับปลั๊กอินทุกตัว"""
    for path in GRADLE_FILES:
        if not path.exists():
            continue
        text = path.read_text(encoding="utf-8")
        patched, count = re.subn(
            r"compileSdk\s*(=\s*)?flutter\.compileSdkVersion",
            f"compileSdk = {COMPILE_SDK}",
            text,
        )
        if count:
            path.write_text(patched, encoding="utf-8")
            print(f"[patch_android] {path} -> compileSdk {COMPILE_SDK}")
        else:
            print(f"[patch_android] {path}: ไม่พบ compileSdk ที่ต้องแก้", file=sys.stderr)


def main() -> int:
    if not MANIFEST.exists():
        print(f"[patch_android] ไม่พบ {MANIFEST} — รัน flutter create ก่อน", file=sys.stderr)
        return 1

    patch_compile_sdk()

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
