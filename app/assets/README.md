วางไฟล์เสียงเตือนชื่อ `alarm.wav` (หรือ .mp3 แล้วแก้ชื่อใน `lib/services/alarm_service.dart`) ไว้ในโฟลเดอร์นี้

ถ้าไม่มีไฟล์ แอปจะเตือนด้วยการสั่นอย่างเดียว โดยไม่ crash
(`AlarmService._fire()` จับ error จาก `play()` ไว้แล้ว)
