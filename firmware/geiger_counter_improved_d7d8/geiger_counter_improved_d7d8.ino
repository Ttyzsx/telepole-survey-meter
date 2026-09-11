/*
 * ไกเกอร์เคาน์เตอร์ LND712 — เวอร์ชันปรับปรุง สำหรับวงจรที่บัดกรีไปแล้ว
 *
 * *** ใช้ตัวนี้ถ้าบัดกรี HC-05 ไว้ที่ D7/D8 แล้ว ***
 * ไม่ต้องแก้สายสักเส้น จอกับบลูทูธทำงานพร้อมกันได้
 *
 * ไฟล์พี่น้องในโปรเจกต์:
 *   geiger_counter_manual/         ต้นฉบับถอดจากคู่มืออาจารย์ (ปิดบลูทูธไว้)
 *   geiger_counter_improved/       เวอร์ชันย้าย HC-05 ไป D0/D1 (ต้องแก้สาย)
 *   geiger_counter_improved_d7d8/  <-- ไฟล์นี้ คาสาย D7/D8 เดิม
 *
 * =============================================================
 * ทำไมต้องมีไฟล์นี้
 * =============================================================
 *
 * ปัญหาเดิม: เปิดบลูทูธแล้วจอดำสนิท คอมไพล์ผ่านแต่รันไม่ขึ้น
 *
 *   Adafruit_SSD1306::begin() ขอ framebuffer 1024 ไบต์ด้วย malloc ตอนรัน
 *   avr-libc กันพื้นที่ให้ stack อีก 128 ไบต์ (__malloc_margin)
 *   => ต้องมีแรมว่าง >= 1152 ไบต์ ตอนเรียก begin() ไม่งั้นค้าง for(;;)
 *
 *   ของเดิมเปิดบลูทูธแล้วเหลือ 1208 ไบต์ เกินมาแค่ 56 ไบต์ ไม่พอ
 *
 * ทางแก้มีสองทาง แล้วแต่ว่าแก้สายได้หรือไม่:
 *
 *   ทาง 1  ย้าย HC-05 ไป UART ฮาร์ดแวร์ D0/D1  -> คืนแรม 117 ไบต์
 *          ดูไฟล์ geiger_counter_improved/  ** ต้องแก้สาย **
 *
 *   ทาง 2  เปลี่ยนไลบรารีจอ ทุบ framebuffer 1024 ไบต์ทิ้ง  <-- ไฟล์นี้เลือกทางนี้
 *          ** ไม่ต้องแก้สาย ** SoftwareSerial อยู่ที่ D7/D8 ต่อไปได้
 *
 * framebuffer ใหญ่กว่า SoftwareSerial เกือบ 9 เท่า ทุบก้อนนี้จึงคุ้มกว่ามาก
 *
 * SSD1306Ascii เขียนตัวอักษรลงจอตรง ๆ ผ่าน I2C ทีละตัว **ไม่จองบัฟเฟอร์เลย**
 * แปลว่าไม่มี malloc ตอนรัน ปัญหา "จอไม่ขึ้นเพราะแรมไม่พอ" หายไปทั้งคลาส
 * ไม่ใช่แค่รอดหวุดหวิด แต่คือไม่มีทางเกิดได้อีก
 *
 * =============================================================
 * ผลลัพธ์ด้านแรม (วัดด้วย arduino-cli บอร์ด arduino:avr:uno)
 * =============================================================
 *
 *   ไลบรารีจอ            RAM เหลือ   flash   จอง framebuffer
 *   Adafruit_SSD1306       1208       66%     1024 ไบต์  <-- ตัวปัญหา
 *   U8g2 page buffer       1251       52%     ไม่จอง
 *   SSD1306Ascii           1572       42%     ไม่จอง     <-- ไฟล์นี้
 *
 *   ได้แรมคืน 364 ไบต์ และ flash ลดจาก 66% เหลือ 42%
 *
 * =============================================================
 * ต้องติดตั้งไลบรารีเพิ่ม 1 ตัวก่อนคอมไพล์
 * =============================================================
 *
 *   Arduino IDE -> Tools -> Manage Libraries -> ค้นหา "SSD1306Ascii"
 *   ของ Bill Greiman  (ทดสอบด้วยเวอร์ชัน 1.3.5)
 *
 *   ไลบรารี Adafruit_SSD1306 กับ Adafruit_GFX ไฟล์นี้ไม่ใช้แล้ว
 *   แต่ไม่ต้องถอนออก ไฟล์อื่นในโปรเจกต์ยังใช้อยู่
 *
 * =============================================================
 * การต่อสาย -- เหมือนเดิมทุกเส้น ไม่ต้องแก้อะไร
 * =============================================================
 *
 *   จอ OLED I2C  ->  A4 (SDA), A5 (SCL)
 *   พัลส์จากบอร์ด HV (CN1)  ->  D2
 *   ปุ่ม Select / Up / Down  ->  D3 / D4 / D5
 *   buzzer  ->  D6
 *   HC-05 TX -> D7 , HC-05 RX <- D8      ** คาเดิม ไม่ต้องย้าย **
 *
 * บอร์ด: Arduino Pro Mini 5V 16MHz หรือ Uno (ATmega328P เหมือนกัน ขาเหมือนกัน)
 *
 * =============================================================
 * ข้อจำกัดที่ยังเหลืออยู่ กับไฟล์นี้
 * =============================================================
 *
 * SoftwareSerial ปิด interrupt ขณะส่งข้อมูล พัลส์ที่เข้ามาช่วงนั้นจะไม่ถูกนับ
 * ส่งครั้งละราว 24 ไบต์ ที่ 9600 baud = ปิด interrupt ราว 25 ms
 * รอบส่งคือทุก 10 วินาที (SAMPLE_TIME) => พัลส์หายราว 0.25%
 *
 * ต่ำกว่าความคลาดเคลื่อนทางสถิติของการนับรังสีเองมาก ใช้งานจริงไม่ต้องกังวล
 * (ถ้าวันไหนลดรอบส่งเหลือทุก 1 วินาที ตัวเลขนี้จะขึ้นเป็นราว 2.5%
 *  ตอนนั้นค่อยพิจารณาย้ายไป UART ฮาร์ดแวร์ตามไฟล์ geiger_counter_improved/)
 */

#include <Wire.h>
#include <SSD1306Ascii.h>
#include <SSD1306AsciiWire.h>
#include <SoftwareSerial.h>

// =============================================================
// สวิตช์ตั้งค่า
// =============================================================

// 1 = พิมพ์ข้อความดีบัก (แรมว่าง ฯลฯ) ออกทาง USB
// 0 = ปิด ประหยัดแรมอีก 157 ไบต์  <-- ค่าปกติ
//
// บลูทูธอยู่บน SoftwareSerial แยกต่างหาก เปิดดีบักไม่กวนสตรีมบลูทูธ
#define DEBUG_SERIAL 0

// ขอบพัลส์ที่จะนับ -- คู่มือใช้ RISING
// ถ้าวัดขา CN1 แล้วพบว่าปกตินิ่งที่ 5V ต้องเปลี่ยนเป็น FALLING
#define PULSE_EDGE RISING

// ---------- ตั้งค่าหน้าจอ OLED ----------
#define OLED_ADDR 0x3C   // I2C address ของจอ SSD1306
SSD1306AsciiWire oled;

// ---------- กำหนดขาต่ออุปกรณ์ ----------
#define GEIGER_PIN 2    // ขาสัญญาณ Pulse จากโมดูล HV (interrupt 0)
#define BUTTON_SEL 3    // ปุ่ม Select (Enter / OK)
#define BUTTON_UP  4    // ปุ่ม เพิ่มค่า
#define BUTTON_DN  5    // ปุ่ม ลดค่า
#define BUZZER_PIN 6    // ขาควบคุมเสียงเตือน
#define BT_RX 7         // ขา RX ของ Arduino (ต่อกับ TX ของ HC-05)
#define BT_TX 8         // ขา TX ของ Arduino (ต่อกับ RX ของ HC-05)

SoftwareSerial bluetooth(BT_RX, BT_TX);   // RX, TX

// ---------- ค่าคงที่หลัก ----------
const unsigned long SAMPLE_TIME = 10000;              // เก็บตัวอย่างทุก 10 วินาที (ms)
const float MULTIPLIER = 60000.0 / SAMPLE_TIME;       // เปลี่ยน CPS เป็น CPM
const float DEFAULT_CONV_FACTOR = 0.00833;            // Conversion factor สำหรับ LND712
const float DEFAULT_BACKGROUND = 20.0;                // ค่ารังสีพื้นหลังเริ่มต้น (CPM)
const float DEFAULT_ALERT_THRESHOLD = 1.0;            // ค่าเตือนเริ่มต้น (uSv/h)

// ---------- ตัวแปรส่วนกลาง ----------
volatile unsigned long pulseCount = 0;   // จำนวนพัลส์ที่ตรวจจับได้
unsigned long lastSampleTime = 0;
float cpm = 0.0;
float doseRate = 0.0;

// ตัวแปรสำหรับการตั้งค่า
float convFactor = DEFAULT_CONV_FACTOR;
float background = DEFAULT_BACKGROUND;
float alertThreshold = DEFAULT_ALERT_THRESHOLD;

// สถานะเมนู
int menuMode = 0;   // 0 = หน้าหลัก, 1 = แก้ไข Conversion Factor,
                    // 2 = แก้ไข Background, 3 = แก้ไข Alert Threshold
int lastMenuMode = -1;   // ใช้ตรวจว่าเมนูเปลี่ยน เพื่อวาดใหม่ทันทีไม่ต้องรอครบรอบ

// แยกตัวจับเวลา debounce ให้แต่ละปุ่ม ของเดิมใช้ตัวเดียวร่วมกันทั้งสามปุ่ม
// ทำให้กด Select แล้วรีบกด Up ไม่ติด ต้องรอ 200 ms
// เรียงตามปุ่ม: [0] = SEL, [1] = UP, [2] = DN
unsigned long lastButtonTime[3] = {0, 0, 0};
const unsigned long debounceDelay = 200;   // กันการกระเด้งของปุ่ม (ms)

// ตัวแปรสำหรับการเตือน
bool alertActive = false;
const unsigned long alertDuration = 500;   // เสียงดัง 0.5 วินาที

#if DEBUG_SERIAL
// -------------------------------------------------------------
// คืนค่าจำนวนไบต์ว่างระหว่าง heap กับ stack ณ ขณะนั้น
// ไฟล์นี้ไม่มี malloc แล้ว ตัวเลขจึงควรนิ่งตลอด ไม่ลดลงเรื่อย ๆ
// -------------------------------------------------------------
int freeRam() {
  extern int __heap_start, *__brkval;
  int v;
  return (int) &v - (__brkval == 0 ? (int) &__heap_start : (int) __brkval);
}
#endif

// -------------------------------------------------------------
// ฟังก์ชัน Interrupt: ทำงานทุกครั้งที่เกิดพัลส์จากหลอดไกเกอร์
// -------------------------------------------------------------
void countPulse() {
  pulseCount++;
}

// -------------------------------------------------------------
// อ่านสถานะปุ่ม (พร้อม debounce แยกรายปุ่ม)
// slot = ช่องเก็บเวลาของปุ่มนั้น 0..2
// -------------------------------------------------------------
int readButton(int pin, int slot) {
  if (digitalRead(pin) == LOW) {   // ปุ่มต่อแบบ Active Low (กด = LOW)
    if ((millis() - lastButtonTime[slot]) > debounceDelay) {
      lastButtonTime[slot] = millis();
      return 1;
    }
  }
  return 0;
}

// -------------------------------------------------------------
// ส่งเสียงเตือนเมื่อรังสีเกินค่า Alert Threshold
// -------------------------------------------------------------
void triggerAlert() {
  if (!alertActive) {
    alertActive = true;
    tone(BUZZER_PIN, 2000, alertDuration);   // เสียง 2000Hz นาน 0.5 วินาที
  }
}

// -------------------------------------------------------------
// อัปเดตหน้าจอ OLED แสดงค่า CPM, uSv/h และสถานะ
//
// SSD1306Ascii ไม่มีบัฟเฟอร์ จึงเขียนทับทีละบรรทัดแล้วลบส่วนที่เหลือ
// ด้วย clearToEOL() แทนการ clear() ทั้งจอ ไม่งั้นจอจะกะพริบทุกครั้งที่อัปเดต
// -------------------------------------------------------------
void updateDisplay() {
  oled.setCursor(0, 0);
  oled.print(F("CPM: "));
  oled.print(cpm, 0);
  oled.clearToEOL();

  oled.setCursor(0, 1);
  oled.print(F("Dose: "));
  oled.print(doseRate, 2);
  oled.print(F(" uSv/h"));
  oled.clearToEOL();

  oled.setCursor(0, 2);
  oled.print(F("Alert: "));
  oled.print(alertThreshold, 2);
  oled.print(F(" uSv/h"));
  oled.clearToEOL();

  oled.setCursor(0, 4);
  oled.print(F("Conv: "));
  oled.print(convFactor, 5);
  oled.clearToEOL();

  oled.setCursor(0, 6);
  if (menuMode != 0) {
    oled.print(F("Menu: "));
    switch (menuMode) {
      case 1: oled.print(F("Conv Factor"));  break;
      case 2: oled.print(F("Background"));   break;
      case 3: oled.print(F("Alert Thresh")); break;
    }
  }
  oled.clearToEOL();
}

// -------------------------------------------------------------
// ส่งข้อมูลทางบลูทูธไปยังสมาร์ทโฟน
// รูปแบบ: cpm=123;uSv/h=1.03
//
// ใช้ dtostrf แปลง float เป็นข้อความก่อน
// เพราะ %f ของ snprintf ใช้ไม่ได้บน Arduino AVR (ได้ ? แทนตัวเลข)
// ของเดิมในคู่มือใช้ %f จึงส่งออกมาเป็น cpm=?;uSv/h=? มาตลอด
// -------------------------------------------------------------
void sendBluetoothData() {
  char bufCpm[12];
  char bufDose[12];
  dtostrf(cpm, 0, 0, bufCpm);        // ทศนิยม 0 ตำแหน่ง
  dtostrf(doseRate, 0, 2, bufDose);  // ทศนิยม 2 ตำแหน่ง

  // ข้อความยาวสุดราว 24 ตัวอักษร buffer 32 พอเหลือเฟือ
  char buffer[32];
  snprintf(buffer, sizeof(buffer), "cpm=%s;uSv/h=%s\n", bufCpm, bufDose);
  bluetooth.print(buffer);
}

// -------------------------------------------------------------
// จัดการเมนูการตั้งค่าผ่านปุ่มกด
// -------------------------------------------------------------
void handleMenu() {
  if (readButton(BUTTON_SEL, 0)) {
    // กดปุ่ม Select: เปลี่ยนโหมดเมนู (วนกลับ)
    menuMode = (menuMode + 1) % 4;
  }

  // ถ้าอยู่ในโหมดเมนู (menuMode != 0) ให้ปรับค่าด้วยปุ่ม Up/Down
  if (menuMode == 1) {
    if (readButton(BUTTON_UP, 1)) convFactor += 0.0001;
    if (readButton(BUTTON_DN, 2) && convFactor > 0) convFactor -= 0.0001;
  }
  else if (menuMode == 2) {
    if (readButton(BUTTON_UP, 1)) background += 1.0;
    if (readButton(BUTTON_DN, 2) && background > 0) background -= 1.0;
  }
  else if (menuMode == 3) {
    if (readButton(BUTTON_UP, 1)) alertThreshold += 0.1;
    if (readButton(BUTTON_DN, 2) && alertThreshold > 0) alertThreshold -= 0.1;
  }
}

// -------------------------------------------------------------
// setup() ทำงานครั้งแรกเมื่อเริ่มต้น
// -------------------------------------------------------------
void setup() {
  bluetooth.begin(9600);    // HC-05 ค่าเริ่มต้นจากโรงงานคือ 9600 baud

#if DEBUG_SERIAL
  Serial.begin(9600);
  Serial.print(F("Free RAM at boot: "));
  Serial.println(freeRam());
#endif

  // เริ่มต้นจอ OLED
  // ไม่มีการ malloc จึงไม่มีค่าที่ต้องเช็คว่าล้มเหลว ต่างจาก Adafruit_SSD1306
  Wire.begin();
  Wire.setClock(400000L);              // I2C ความเร็วสูง ทำให้วาดจอไหลลื่นขึ้น
  oled.begin(&Adafruit128x64, OLED_ADDR);
  oled.setFont(System5x7);
  oled.clear();

  // ตั้งค่าขา
  pinMode(GEIGER_PIN, INPUT);
  pinMode(BUTTON_SEL, INPUT_PULLUP);
  pinMode(BUTTON_UP, INPUT_PULLUP);
  pinMode(BUTTON_DN, INPUT_PULLUP);
  pinMode(BUZZER_PIN, OUTPUT);

  // เปิดใช้งาน Interrupt สำหรับขา D2 (ขา 2 = interrupt 0)
  attachInterrupt(digitalPinToInterrupt(GEIGER_PIN), countPulse, PULSE_EDGE);

  // แสดงข้อความเริ่มต้น
  oled.setCursor(0, 0);
  oled.println(F("Geiger Counter"));
  oled.println(F("LND712 Ready"));
  delay(2000);
  oled.clear();

  lastSampleTime = millis();
}

// -------------------------------------------------------------
// loop() ทำงานวนซ้ำตลอดเวลา
// -------------------------------------------------------------
void loop() {
  // จัดการเมนูและปุ่มกด
  handleMenu();

  // ถ้าเพิ่งกดเปลี่ยนเมนู ให้วาดจอใหม่ทันที ไม่ต้องรอครบ 10 วินาที
  // ของเดิมกดปุ่มแล้วจอนิ่ง เหมือนปุ่มเสีย ทั้งที่ค่าเปลี่ยนไปแล้ว
  if (menuMode != lastMenuMode) {
    lastMenuMode = menuMode;
    updateDisplay();
  }

  // ทุก ๆ SAMPLE_TIME (10 วินาที) ให้คำนวณ CPM, Dose Rate และแสดงผล
  if (millis() - lastSampleTime >= SAMPLE_TIME) {
    // ปิด Interrupt ชั่วคราวขณะอ่านค่า pulseCount
    noInterrupts();
    unsigned long counts = pulseCount;
    pulseCount = 0;
    interrupts();

    // คำนวณ CPM และ Dose Rate
    cpm = counts * MULTIPLIER;
    float adjustedCPM = cpm - background;
    if (adjustedCPM < 0) adjustedCPM = 0;
    doseRate = adjustedCPM * convFactor;

    // ตรวจสอบการเตือน
    if (doseRate >= alertThreshold) {
      triggerAlert();
    } else {
      alertActive = false;
    }

    updateDisplay();
    sendBluetoothData();

    lastSampleTime = millis();
  }

  // วนลูปเล็กน้อยเพื่อให้ปุ่มทำงานได้ทันที
  delay(10);
}
