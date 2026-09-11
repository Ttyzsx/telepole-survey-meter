/*
 * ไกเกอร์เคาน์เตอร์ LND712 — เวอร์ชันปรับปรุง (จอ + บลูทูธ ทำงานพร้อมกัน)
 *
 * ต่อยอดจาก firmware/geiger_counter_manual/ ซึ่งถอดความจากคู่มืออาจารย์
 * ไฟล์ต้นทางยังอยู่ครบ ไม่ได้แก้ ใช้อ้างอิงเทียบได้ตลอด
 *
 * *** ไฟล์นี้ไม่ใช่ firmware ของเครื่อง Telepole ***
 * ของเราอยู่ที่ firmware/telepole_gm/ ซึ่งไม่มีจอและไม่มีปุ่ม
 *
 * =============================================================
 * ปัญหาของไฟล์เดิม และวิธีที่ไฟล์นี้แก้
 * =============================================================
 *
 * [A] เปิดบลูทูธแล้วจอดำสนิท  <-- ปัญหาหลักที่ทำให้ต้องมีไฟล์นี้
 *
 *     Adafruit_SSD1306::begin() ขอ framebuffer 1024 ไบต์ด้วย malloc ตอนรัน
 *     avr-libc กันพื้นที่ให้ stack อีก 128 ไบต์ (__malloc_margin)
 *     => ต้องมีแรมว่างอย่างน้อย 1152 ไบต์ ตอนเรียก begin()
 *
 *     ของเดิมเปิดบลูทูธแล้วเหลือ 1208 ไบต์ = เกินมาแค่ 56 ไบต์
 *     stack กินอีกนิดเดียวก็ไม่พอ malloc คืน NULL แล้วค้างที่ for(;;) ตลอดกาล
 *     อาการหลอกมาก เพราะคอมไพล์ผ่านฉลุย ไม่มี error สักบรรทัด
 *
 *     ตัวการคือ SoftwareSerial กินแรม 117 ไบต์
 *       _receive_buffer 64 + object 31 + vtable 18 + เศษ
 *     และมันถูกจองตั้งแต่ตอนคอมไพล์ ไม่เกี่ยวกับว่าเสียบ HC-05 จริงหรือไม่
 *
 *     >>> วิธีแก้: ย้าย HC-05 ไปใช้ UART ฮาร์ดแวร์ (D0/D1) เลิกใช้ SoftwareSerial
 *         ATmega328P มีวงจร UART อยู่ในชิปแล้ว ไม่ต้องจองบัฟเฟอร์ก้อนใหม่
 *         ได้แรมคืน 117 ไบต์ โดยที่บลูทูธยังใช้ได้ครบ
 *
 * [B] บลูทูธส่งออกมาเป็นเครื่องหมายคำถาม
 *
 *     ของเดิมใช้  snprintf(buf, n, "cpm=%.0f;uSv/h=%.2f\n", cpm, doseRate)
 *     Arduino AVR ตัด float ออกจาก printf โดยค่าเริ่มต้น (ประหยัด flash)
 *     ผลคือส่งออกไปจริงเป็น  cpm=?;uSv/h=?  ตัวเลขหายหมด
 *
 *     >>> วิธีแก้: ใช้ dtostrf แปลง float เป็นข้อความก่อน (วิธีมาตรฐานของ AVR)
 *
 * [C] ปุ่มสามปุ่มใช้ตัวจับเวลา debounce ร่วมกันตัวเดียว
 *
 *     กดปุ่มหนึ่งแล้วอีก 200 ms ปุ่มอื่นจะกดไม่ติด
 *     เห็นชัดตอนกด Select เข้าโหมดแล้วรีบกด Up
 *
 *     >>> วิธีแก้: แยกตัวจับเวลาให้แต่ละปุ่ม (เปลืองแรมเพิ่ม 8 ไบต์)
 *
 * [D] ข้อความบนจอถูกก๊อปมากองใน SRAM ตั้งแต่บูต
 *
 *     >>> วิธีแก้: ครอบ F() ให้ข้อความคงที่ทุกจุด เก็บไว้ใน flash แทน
 *         (ยกมาจากไฟล์เดิมที่แก้ไว้แล้ว)
 *
 * =============================================================
 * ผลลัพธ์ด้านแรม (วัดด้วย arduino-cli บอร์ด arduino:avr:uno)
 * =============================================================
 *
 *   คู่มือเดิม + บลูทูธ        1208 ไบต์   เกินเส้น  +56   จอดำ
 *   คู่มือเดิม ปิดบลูทูธ       1325 ไบต์   เกินเส้น +173   จอติด แต่ไม่มีบลูทูธ
 *   ไฟล์นี้ จอ + บลูทูธ        1431 ไบต์   เกินเส้น +279   ได้ทั้งคู่
 *
 *   (เส้นตายคือ 1152 ไบต์ ต่ำกว่านี้จอไม่ขึ้นแน่นอน)
 *
 * =============================================================
 * การต่อสาย -- เปลี่ยนจากเดิม อ่านก่อนเสียบ
 * =============================================================
 *
 *   HC-05 TX  ->  Arduino D0 (RX)     ** เดิมคือ D7 **
 *   HC-05 RX  <-  Arduino D1 (TX)     ** เดิมคือ D8 **
 *   HC-05 VCC ->  5V
 *   HC-05 GND ->  GND
 *
 *   D7 กับ D8 ว่างแล้ว เอาไปใช้อย่างอื่นได้
 *
 *   [!] ต้องถอด HC-05 ออกทุกครั้งก่อนแฟลชโปรแกรม
 *       เพราะตัวอัปโหลดใช้ D0/D1 เส้นเดียวกัน ถ้าไม่ถอดจะอัปโหลดไม่ผ่าน
 *       (บอร์ดไม่พัง แค่อัปโหลดไม่ได้ ถอดแล้วลองใหม่ได้เลย)
 *
 *   [!] ขา RX ของ HC-05 รับแรงดัน 3.3V
 *       ถ้าโมดูลไม่มีวงจรแบ่งแรงดันในตัว ต้องคั่นตัวต้านทานจาก D1 ก่อน
 *       (บอร์ด HC-05 สีน้ำเงินส่วนใหญ่มีมาให้แล้ว เช็คก่อนต่อ)
 *
 * ส่วนอื่นต่อเหมือนเดิมทุกเส้น: จอ I2C (A4/A5), พัลส์ D2, ปุ่ม D3/D4/D5, buzzer D6
 *
 * บอร์ด: Arduino Pro Mini 5V 16MHz หรือ Uno (ATmega328P เหมือนกัน ขาเหมือนกัน)
 * ไลบรารี: Adafruit SSD1306, Adafruit GFX Library
 */

#include <Wire.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_GFX.h>

// =============================================================
// สวิตช์ตั้งค่า
// =============================================================

// 1 = พิมพ์ข้อความดีบัก (แรมว่าง ฯลฯ) ออกทาง UART
// 0 = ปิด เพื่อไม่ให้ข้อความดีบักปนเข้าไปในสตรีมบลูทูธ  <-- ค่าปกติ
//
// เวลาจะดีบัก: ตั้งเป็น 1, ถอด HC-05 ออก, เสียบ USB, เปิด Serial Monitor 9600
#define DEBUG_SERIAL 0

// ขอบพัลส์ที่จะนับ -- คู่มือใช้ RISING
// ถ้าวัดขา CN1 แล้วพบว่าปกตินิ่งที่ 5V ต้องเปลี่ยนเป็น FALLING
#define PULSE_EDGE RISING

// ---------- ตั้งค่าหน้าจอ OLED ----------
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_ADDR 0x3C   // I2C address ของจอ SSD1306
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

// ---------- กำหนดขาต่ออุปกรณ์ ----------
#define GEIGER_PIN 2    // ขาสัญญาณ Pulse จากโมดูล HV (interrupt 0)
#define BUTTON_SEL 3    // ปุ่ม Select (Enter / OK)
#define BUTTON_UP  4    // ปุ่ม เพิ่มค่า
#define BUTTON_DN  5    // ปุ่ม ลดค่า
#define BUZZER_PIN 6    // ขาควบคุมเสียงเตือน
// บลูทูธใช้ UART ฮาร์ดแวร์ D0/D1 ไม่ต้องประกาศขา และไม่ต้อง include SoftwareSerial

// bluetooth เป็นชื่อเรียกอีกชื่อของ Serial เฉย ๆ ไม่กินแรมเพิ่มสักไบต์
// ทำไว้เพื่อให้อ่านโค้ดแล้วรู้ว่าบรรทัดไหนคุยกับ HC-05
#define bluetooth Serial

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

// สถานะปุ่มและเมนู
int menuMode = 0;   // 0 = หน้าหลัก, 1 = แก้ไข Conversion Factor,
                    // 2 = แก้ไข Background, 3 = แก้ไข Alert Threshold

// [C] แยกตัวจับเวลา debounce ให้แต่ละปุ่ม ของเดิมใช้ตัวเดียวร่วมกันทั้งสามปุ่ม
// เรียงตามขา: [0] = BUTTON_SEL, [1] = BUTTON_UP, [2] = BUTTON_DN
unsigned long lastButtonTime[3] = {0, 0, 0};
const unsigned long debounceDelay = 200;   // กันการกระเด้งของปุ่ม (ms)

// ตัวแปรสำหรับการเตือน
bool alertActive = false;
const unsigned long alertDuration = 500;   // เสียงดัง 0.5 วินาที

#if DEBUG_SERIAL
// -------------------------------------------------------------
// คืนค่าจำนวนไบต์ว่างระหว่าง heap กับ stack ณ ขณะนั้น
// ใช้ดูว่าเหลือพอให้ display.begin() ขอ framebuffer 1024 ไบต์หรือไม่
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
// -------------------------------------------------------------
void updateDisplay() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);

  // แสดง CPM และ Dose Rate
  display.print(F("CPM: "));
  display.println(cpm, 0);
  display.print(F("Dose: "));
  display.print(doseRate, 2);
  display.println(F(" uSv/h"));

  // แสดงค่า Alert Threshold และ Conversion Factor
  display.print(F("Alert: "));
  display.print(alertThreshold, 2);
  display.print(F(" uSv/h"));

  display.setCursor(0, 40);
  display.print(F("Conv: "));
  display.print(convFactor, 5);

  // หากกำลังอยู่ในโหมดเมนู ให้แสดงข้อความแจ้ง
  if (menuMode != 0) {
    display.setCursor(0, 52);
    display.print(F("Menu Mode: "));
    switch (menuMode) {
      case 1: display.print(F("Conv Factor")); break;
      case 2: display.print(F("Background"));  break;
      case 3: display.print(F("Alert Thresh")); break;
    }
  }

  display.display();
}

// -------------------------------------------------------------
// ส่งข้อมูลทางบลูทูธไปยังสมาร์ทโฟน
// รูปแบบ: cpm=123;uSv/h=1.03
//
// [B] ใช้ dtostrf แปลง float เป็นข้อความก่อน
//     เพราะ %f ของ snprintf ใช้ไม่ได้บน Arduino AVR (ได้ ? แทนตัวเลข)
// -------------------------------------------------------------
void sendBluetoothData() {
  char bufCpm[12];
  char bufDose[12];
  dtostrf(cpm, 0, 0, bufCpm);        // ทศนิยม 0 ตำแหน่ง
  dtostrf(doseRate, 0, 2, bufDose);  // ทศนิยม 2 ตำแหน่ง

  // ข้อความยาวสุดประมาณ 24 ตัวอักษร buffer 32 พอเหลือเฟือ
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
  // UART ตัวเดียวนี้ใช้ทั้งคุยกับ HC-05 และพิมพ์ดีบัก
  // HC-05 ค่าเริ่มต้นจากโรงงานคือ 9600 baud
  bluetooth.begin(9600);

#if DEBUG_SERIAL
  // ต้องเหลืออย่างน้อย 1024 + 128 = 1152 ไบต์ จอถึงจะเริ่มได้
  Serial.print(F("Free RAM before begin: "));
  Serial.println(freeRam());
#endif

  // เริ่มต้นจอ OLED
  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) {
#if DEBUG_SERIAL
    Serial.println(F("SSD1306 allocation failed"));
    Serial.print(F("Free RAM at failure: "));
    Serial.println(freeRam());
#endif
    for (;;);   // หยุดทำงานหากจอแสดงผลไม่เริ่ม
  }

#if DEBUG_SERIAL
  Serial.print(F("Display OK. Free RAM after begin: "));
  Serial.println(freeRam());
#endif

  display.clearDisplay();
  display.display();
  delay(1000);

  // ตั้งค่าขา
  pinMode(GEIGER_PIN, INPUT);
  pinMode(BUTTON_SEL, INPUT_PULLUP);
  pinMode(BUTTON_UP, INPUT_PULLUP);
  pinMode(BUTTON_DN, INPUT_PULLUP);
  pinMode(BUZZER_PIN, OUTPUT);

  // เปิดใช้งาน Interrupt สำหรับขา D2 (ขา 2 = interrupt 0)
  attachInterrupt(digitalPinToInterrupt(GEIGER_PIN), countPulse, PULSE_EDGE);

  // แสดงข้อความเริ่มต้น
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 0);
  display.println(F("Geiger Counter"));
  display.println(F("LND712 Ready"));
  display.display();
  delay(2000);

  lastSampleTime = millis();
}

// -------------------------------------------------------------
// loop() ทำงานวนซ้ำตลอดเวลา
// -------------------------------------------------------------
void loop() {
  // จัดการเมนูและปุ่มกด
  handleMenu();

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
