/*
 * Telepole Radiation Survey Meter - Firmware
 * Target : Arduino Uno R3 (ATmega328P) + HC-05 Bluetooth (SPP)
 *          ชิปตัวเดียวกับ Nano ขาที่ใช้จึงเหมือนกันทุกขา คอมไพล์ด้วย board "Arduino Uno"
 *
 * - นับพัลส์จากวงจรหัววัด GM ด้วย Hardware Interrupt (INT0 = D2)
 * - คำนวณ CPM จากหน้าต่างเลื่อน (rolling window) 60 วินาที
 * - แปลง CPM -> Dose Rate (uSv/h) ด้วยค่าคงที่ของหลอด GM
 * - สะสมปริมาณรังสี (uSv) โดยอินทิเกรตทุกช่วง 1 วินาที
 * - ส่ง CSV ออก HC-05 ทุก 1 วินาที : "CPM,uSv_h,Accumulated_uSv,CPS\n"
 *   ช่อง CPS = พัลส์ดิบของวินาทีนั้น ไม่ผ่านการเฉลี่ย แอปใช้ขับกราฟเรียลไทม์และเสียงคลิก
 * - รับคำสั่งจากแอป : 'R' = reset ค่าสะสม, 'Z' = reset ทั้งหมด, '?' = ส่งข้อมูลทันที
 */

#include <SoftwareSerial.h>

// ---------------- Configuration ----------------
const uint8_t  PIN_GM_PULSE   = 2;    // ต้องเป็น D2 หรือ D3 เท่านั้น (INT0 / INT1)
const uint8_t  PIN_BT_RX      = 10;   // Uno D10   <- HC-05 TXD
const uint8_t  PIN_BT_TX      = 11;   // Uno D11   -> HC-05 RXD (ผ่าน voltage divider)
const uint8_t  PIN_BUZZER     = 8;    // บัซเซอร์/LED ติ๊กเวลาเจอพัลส์ (ตัวเลือก)
const uint8_t  PIN_LED_ALARM  = 9;

// ขอบสัญญาณที่ใช้ trigger — ขึ้นกับวงจร interface ของหัววัด
//   FALLING = พัลส์ active-low (transistor/optocoupler ดึงลง GND) ใช้กับ INPUT_PULLUP
//   RISING  = พัลส์ active-high
// ถ้าตั้งผิดขอบ จะยังนับได้แต่ค่าอาจเพี้ยนหรือนับไม่ครบ ควรยืนยันด้วยออสซิลโลสโคป
const int PULSE_EDGE = FALLING;

// ค่าคงที่แปลงหน่วยของหลอด GM
//   หลอดที่เครื่องนี้ใช้จริงคือ *** LND 712 ***
//     datasheet ระบุ gamma sensitivity 18 CPS ต่อ 1 mR/h (อ้างอิง Co-60)
//     18 CPS = 1080 CPM  และ 1 mR/h ~ 10 uSv/h  ->  108 CPM ต่อ 1 uSv/h
//
//   หลอดอื่นเผื่อไว้เทียบ (อ้างอิง Cs-137 662 keV):
//     J305 / J305beta / M4011 ~ 153.8 CPM ต่อ 1 uSv/h
//     SBM-20                  ~ 150.5 CPM ต่อ 1 uSv/h
//
//   ค่านี้เป็นค่าตั้งต้นจาก datasheet ไม่ใช่ค่าที่สอบเทียบกับเครื่องมาตรฐานแล้ว
//   แอปมีฟังก์ชันสอบเทียบภาคสนาม และคำนวณ uSv/h เองจาก CPM
//   ดังนั้นไม่จำเป็นต้อง flash บอร์ดใหม่เมื่อเปลี่ยนค่าสอบเทียบ
const float CPM_PER_USV_H = 108.0f;   // LND 712

const unsigned long REPORT_INTERVAL_MS = 1000UL;  // ส่งข้อมูลทุก 1 วินาที
const uint8_t  WINDOW_SECONDS = 60;               // หน้าต่างเฉลี่ยของ CPM
const unsigned long DEBOUNCE_US = 190UL;          // dead time ของหลอด GM (~190us)
const float ALARM_USV_H = 2.5f;                   // เกณฑ์เตือนที่ตัวเครื่อง

// ---------------- State ----------------
SoftwareSerial bt(PIN_BT_RX, PIN_BT_TX);

volatile unsigned long pulseCount = 0;      // ตัวนับดิบ แก้ไขใน ISR เท่านั้น
volatile unsigned long lastPulseMicros = 0;

uint16_t window[WINDOW_SECONDS];            // จำนวนพัลส์ของแต่ละวินาทีย้อนหลัง
uint8_t  windowIndex = 0;
uint8_t  windowFilled = 0;                  // จำนวนช่องที่มีข้อมูลจริงแล้ว
unsigned long windowSum = 0;                // ผลรวมพัลส์ในหน้าต่าง

float accumulatedUSv = 0.0f;                // ปริมาณรังสีสะสมตั้งแต่เปิดเครื่อง
unsigned long lastReportMs = 0;
unsigned long tickOffMs = 0;                // เวลาปิดเสียงติ๊ก

// ---------------- ISR ----------------
// ยิงเมื่อสัญญาณจากวงจร GM ตกลง (active-low pulse จาก transistor/optocoupler)
void onGeigerPulse() {
  unsigned long now = micros();
  if (now - lastPulseMicros < DEBOUNCE_US) return;   // กัน bounce / ringing
  lastPulseMicros = now;
  pulseCount++;
}

// ---------------- Setup ----------------
void setup() {
  pinMode(PIN_GM_PULSE, INPUT_PULLUP);
  pinMode(PIN_BUZZER, OUTPUT);
  pinMode(PIN_LED_ALARM, OUTPUT);
  digitalWrite(PIN_BUZZER, LOW);
  digitalWrite(PIN_LED_ALARM, LOW);

  for (uint8_t i = 0; i < WINDOW_SECONDS; i++) window[i] = 0;

  Serial.begin(9600);     // debug ผ่าน USB
  bt.begin(9600);         // HC-05 default baud = 9600

  attachInterrupt(digitalPinToInterrupt(PIN_GM_PULSE), onGeigerPulse, PULSE_EDGE);

  bt.println(F("#TELEPOLE,v1.1,CPM,uSv_h,Accumulated_uSv,CPS"));
  Serial.println(F("#TELEPOLE,v1.1,CPM,uSv_h,Accumulated_uSv,CPS"));

  lastReportMs = millis();
}

// ---------------- Helpers ----------------
unsigned long takePulseSnapshot() {
  unsigned long counts;
  noInterrupts();               // อ่านและเคลียร์แบบ atomic
  counts = pulseCount;
  pulseCount = 0;
  interrupts();
  return counts;
}

void pushWindow(uint16_t countsThisSecond) {
  windowSum -= window[windowIndex];
  window[windowIndex] = countsThisSecond;
  windowSum += countsThisSecond;
  windowIndex = (windowIndex + 1) % WINDOW_SECONDS;
  if (windowFilled < WINDOW_SECONDS) windowFilled++;
}

// CPM = (พัลส์รวมในหน้าต่าง / จำนวนวินาทีที่เก็บได้จริง) * 60
// ช่วงแรกที่ยังเก็บไม่ครบ 60 วินาที จะ scale ขึ้นเพื่อให้ตัวเลขใช้งานได้ทันที
float computeCpm() {
  if (windowFilled == 0) return 0.0f;
  return ((float)windowSum / (float)windowFilled) * 60.0f;
}

void handleCommand() {
  while (bt.available()) {
    char c = bt.read();
    if (c == 'R' || c == 'r') {
      accumulatedUSv = 0.0f;
      bt.println(F("#ACK,RESET_DOSE"));
    } else if (c == 'Z' || c == 'z') {
      accumulatedUSv = 0.0f;
      windowSum = 0; windowIndex = 0; windowFilled = 0;
      for (uint8_t i = 0; i < WINDOW_SECONDS; i++) window[i] = 0;
      takePulseSnapshot();
      bt.println(F("#ACK,RESET_ALL"));
    } else if (c == '?') {
      lastReportMs = 0;   // บังคับส่งรอบใหม่ทันที
    }
  }
}

// ช่องที่ 4 (CPS) คือจำนวนพัลส์ดิบของวินาทีที่เพิ่งผ่านไป ไม่ผ่านการเฉลี่ยใด ๆ
// แอปใช้ค่านี้ขับเสียงคลิกและแสดงค่าที่ตอบสนองทันที ต่างจาก CPM ที่เฉลี่ย 60 วินาที
void report(float cpm, float uSvH, uint16_t countsThisSecond) {
  // รูปแบบ: CPM,uSv_h,Accumulated_uSv,CPS
  char line[64];
  char bufCpm[12], bufRate[12], bufDose[12];
  dtostrf(cpm, 0, 1, bufCpm);
  dtostrf(uSvH, 0, 4, bufRate);
  dtostrf(accumulatedUSv, 0, 4, bufDose);
  snprintf(line, sizeof(line), "%s,%s,%s,%u",
           bufCpm, bufRate, bufDose, countsThisSecond);
  bt.println(line);
  Serial.println(line);
}

// ---------------- Loop ----------------
void loop() {
  handleCommand();

  // ปิดเสียงติ๊กหลังผ่านไป 2 ms
  if (tickOffMs && millis() >= tickOffMs) {
    digitalWrite(PIN_BUZZER, LOW);
    tickOffMs = 0;
  }

  unsigned long now = millis();
  if (now - lastReportMs < REPORT_INTERVAL_MS) return;

  // เก็บช่วงเวลาที่ผ่านไปจริง แล้วใช้มันคำนวณค่าสะสม
  // จึงไม่มีปัญหา drift แม้ loop จะมาช้ากว่า 1000 ms พอดี
  unsigned long elapsedMs = now - lastReportMs;
  lastReportMs = now;

  unsigned long counts = takePulseSnapshot();
  if (counts > 65535UL) counts = 65535UL;
  pushWindow((uint16_t)counts);

  float cpm   = computeCpm();
  float uSvH  = cpm / CPM_PER_USV_H;

  // อินทิเกรตปริมาณสะสม: uSv/h * (ms / 3,600,000) = uSv
  accumulatedUSv += uSvH * ((float)elapsedMs / 3600000.0f);

  // สัญญาณเตือนที่ตัวเครื่อง
  digitalWrite(PIN_LED_ALARM, uSvH >= ALARM_USV_H ? HIGH : LOW);
  if (counts > 0) {                       // ติ๊กเมื่อมีพัลส์ในวินาทีนั้น
    digitalWrite(PIN_BUZZER, HIGH);
    tickOffMs = now + 2;
  }

  report(cpm, uSvH, (uint16_t)counts);
}
