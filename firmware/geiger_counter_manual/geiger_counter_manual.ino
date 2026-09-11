/*
 * ไกเกอร์เคาน์เตอร์ด้วย Arduino Pro Mini + LND712
 *
 * ถอดความจาก "คู่มือสร้างไกเกอร์เคาน์เตอร์ด้วย Arduino Pro Mini และ LND712"
 * ที่อาจารย์มอบให้ (PDF สแกน 15 หน้า, ส่วนโค้ดอยู่หน้า 4-12)
 *
 * *** ไฟล์นี้ไม่ใช่ firmware ของเครื่อง Telepole ***
 * ของเราอยู่ที่ firmware/telepole_gm/ ซึ่งไม่มีจอและไม่มีปุ่ม
 * ไฟล์นี้ทำไว้เพื่อให้รันตามคู่มือได้ตรง ๆ
 *
 * ฟีเจอร์ตามคู่มือ:
 *   - นับพัลส์จากหลอด LND712 (ขา D2, interrupt)
 *   - แสดง CPM และ uSv/h บนจอ OLED I2C
 *   - ปุ่มปรับค่า Conversion Factor, Background และ Alert Threshold
 *   - ส่งข้อมูลทาง Bluetooth ไปยังสมาร์ทโฟน
 *   - เสียงเตือนเมื่อรังสีเกินค่า Alert Threshold
 *
 * ไลบรารีที่ต้องติดตั้งใน Arduino IDE ก่อนคอมไพล์:
 *   - Adafruit SSD1306
 *   - Adafruit GFX Library
 *   (SoftwareSerial มีมากับ IDE อยู่แล้ว)
 *
 * บอร์ด: Arduino Pro Mini 5V 16MHz (หรือ Uno ก็ได้ ขาเหมือนกันทุกขา)
 *
 * -------------------------------------------------------------------------
 * หมายเหตุสำคัญ อ่านก่อนใช้ — ดูรายละเอียดท้ายไฟล์
 *   [1] snprintf กับ %f ใช้ไม่ได้บน Arduino AVR โดยค่าเริ่มต้น
 *   [2] setup() ในคู่มือไม่ได้ตั้งสีตัวอักษรก่อนพิมพ์ข้อความเปิดเครื่อง
 *   [3] ปุ่มทั้งสามใช้ตัวจับเวลา debounce ร่วมกันตัวเดียว
 * -------------------------------------------------------------------------
 */

// ---------- [ทดสอบ RAM] สวิตช์เปิด/ปิด Bluetooth ----------
// 0 = ตัด SoftwareSerial ออก ประหยัดแรมประมาณ 117 ไบต์
// 1 = เปิดใช้ Bluetooth ตามปกติ (ทำได้เมื่อย้ายไปใช้ U8g2 page buffer แล้ว)
#define ENABLE_BLUETOOTH 0

#include <Wire.h>
#include <Adafruit_SSD1306.h>
#include <Adafruit_GFX.h>
#if ENABLE_BLUETOOTH
#include <SoftwareSerial.h>
#endif

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
#define BT_RX 7         // ขา RX ของ Arduino (ต่อกับ TX ของ HC-05)
#define BT_TX 8         // ขา TX ของ Arduino (ต่อกับ RX ของ HC-05)

#if ENABLE_BLUETOOTH
SoftwareSerial bluetooth(BT_RX, BT_TX);   // RX, TX
#endif

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
bool buttonPressed = false;
unsigned long lastButtonTime = 0;
const unsigned long debounceDelay = 200;   // กันการกระเด้งของปุ่ม (ms)

// ตัวแปรสำหรับการเตือน
bool alertActive = false;
unsigned long lastAlertTime = 0;
const unsigned long alertDuration = 500;   // เสียงดัง 0.5 วินาที

// -------------------------------------------------------------
// [ทดสอบ RAM] คืนค่าจำนวนไบต์ว่างระหว่าง heap กับ stack ณ ขณะนั้น
// ใช้ดูว่าเหลือพอให้ display.begin() ขอ framebuffer 1024 ไบต์หรือไม่
// -------------------------------------------------------------
int freeRam() {
  extern int __heap_start, *__brkval;
  int v;
  return (int) &v - (__brkval == 0 ? (int) &__heap_start : (int) __brkval);
}

// -------------------------------------------------------------
// ฟังก์ชัน Interrupt: ทำงานทุกครั้งที่เกิดพัลส์จากหลอดไกเกอร์
// -------------------------------------------------------------
void countPulse() {
  pulseCount++;
}

// -------------------------------------------------------------
// อ่านสถานะปุ่ม (พร้อม debounce)
// -------------------------------------------------------------
int readButton(int pin) {
  if (digitalRead(pin) == LOW) {   // สมมติปุ่มต่อแบบ Active Low (กด = LOW)
    if ((millis() - lastButtonTime) > debounceDelay) {
      lastButtonTime = millis();
      return 1;
    }
  }
  return 0;
}

// -------------------------------------------------------------
// แสดงข้อความแจ้งเตือนเมื่อรังสีเกินค่า Alert Threshold
// -------------------------------------------------------------
void triggerAlert() {
  if (!alertActive) {
    alertActive = true;
    lastAlertTime = millis();
    tone(BUZZER_PIN, 2000, alertDuration);   // เสียงความถี่ 2000Hz นาน 0.5 วินาที
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
// ส่งข้อมูลทาง Bluetooth ไปยังสมาร์ทโฟน
// รูปแบบ: cpm=123.45;uSv/h=1.03
// -------------------------------------------------------------
void sendBluetoothData() {
#if ENABLE_BLUETOOTH
  char buffer[50];
  snprintf(buffer, sizeof(buffer), "cpm=%.0f;uSv/h=%.2f\n", cpm, doseRate);
  bluetooth.print(buffer);
#endif
}

// -------------------------------------------------------------
// จัดการเมนูการตั้งค่าผ่านปุ่มกด
// -------------------------------------------------------------
void handleMenu() {
  if (readButton(BUTTON_SEL)) {
    // กดปุ่ม Select: เปลี่ยนโหมดเมนู (วนกลับ)
    menuMode = (menuMode + 1) % 4;
    delay(200);   // หน่วงเล็กน้อยเพื่อป้องกันการกดซ้ำ
  }

  // ถ้าอยู่ในโหมดเมนู (menuMode != 0) ให้ปรับค่าด้วยปุ่ม Up/Down
  if (menuMode == 1) {
    if (readButton(BUTTON_UP)) convFactor += 0.0001;
    if (readButton(BUTTON_DN) && convFactor > 0) convFactor -= 0.0001;
  }
  else if (menuMode == 2) {
    if (readButton(BUTTON_UP)) background += 1.0;
    if (readButton(BUTTON_DN) && background > 0) background -= 1.0;
  }
  else if (menuMode == 3) {
    if (readButton(BUTTON_UP)) alertThreshold += 0.1;
    if (readButton(BUTTON_DN) && alertThreshold > 0) alertThreshold -= 0.1;
  }
}

// -------------------------------------------------------------
// ฟังก์ชัน setup() ทำงานครั้งแรกเมื่อเริ่มต้น
// -------------------------------------------------------------
void setup() {
  Serial.begin(9600);       // Serial Monitor สำหรับดีบัก
#if ENABLE_BLUETOOTH
  bluetooth.begin(9600);    // เริ่มการทำงาน Bluetooth (HC-05 ปกติใช้ 9600 baud)
#endif

  // [ทดสอบ RAM] ต้องเหลืออย่างน้อย 1024 + 128 = 1152 ไบต์ จอถึงจะเริ่มได้
  Serial.print(F("Free RAM before begin: "));
  Serial.println(freeRam());

  // เริ่มต้นจอ OLED
  if(!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDR)) {
    Serial.println(F("SSD1306 allocation failed"));
    Serial.print(F("Free RAM at failure: "));
    Serial.println(freeRam());
    for (;;);   // หยุดทำงานหากจอแสดงผลไม่เริ่ม
  }
  Serial.print(F("Display OK. Free RAM after begin: "));
  Serial.println(freeRam());
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
  attachInterrupt(digitalPinToInterrupt(GEIGER_PIN), countPulse, RISING);

  // แสดงข้อความเริ่มต้น
  display.clearDisplay();
  display.setTextSize(1);                  // [เพิ่มจากคู่มือ] ดูหมายเหตุ [2]
  display.setTextColor(SSD1306_WHITE);     // [เพิ่มจากคู่มือ] ดูหมายเหตุ [2]
  display.setCursor(0, 0);
  display.println(F("Geiger Counter"));
  display.println(F("LND712 Ready"));
  display.display();
  delay(2000);

  lastSampleTime = millis();
}

// -------------------------------------------------------------
// ฟังก์ชัน loop() ทำงานวนซ้ำตลอดเวลา
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

    // อัปเดตหน้าจอ OLED
    updateDisplay();

    // ส่งข้อมูลทาง Bluetooth
    sendBluetoothData();

    // รีเซ็ตเวลา
    lastSampleTime = millis();
  }

  // วนลูปเล็กน้อยเพื่อให้ปุ่มทำงานได้ทันที
  delay(50);
}

/* =============================================================
 * หมายเหตุ 3 ข้อ
 * =============================================================
 *
 * [1] snprintf กับ %f บน Arduino AVR
 *
 *     Arduino core สำหรับ AVR ตัดการรองรับเลขทศนิยมออกจาก printf
 *     เพื่อประหยัดพื้นที่โปรแกรม ผลคือบรรทัดนี้ใน sendBluetoothData()
 *
 *         snprintf(buffer, sizeof(buffer), "cpm=%.0f;uSv/h=%.2f\n", cpm, doseRate);
 *
 *     มักส่งออกมาเป็น  cpm=?;uSv/h=?  แทนที่จะเป็นตัวเลข
 *
 *     ถ้าเจออาการนี้ ให้แทน sendBluetoothData() ด้วยเวอร์ชันนี้แทน
 *     ซึ่งใช้ dtostrf แปลง float เป็นข้อความก่อน (วิธีมาตรฐานของ AVR)
 *
 *         void sendBluetoothData() {
 *           char buffer[50];
 *           char bufCpm[12], bufDose[12];
 *           dtostrf(cpm, 0, 0, bufCpm);
 *           dtostrf(doseRate, 0, 2, bufDose);
 *           snprintf(buffer, sizeof(buffer), "cpm=%s;uSv/h=%s\n", bufCpm, bufDose);
 *           bluetooth.print(buffer);
 *         }
 *
 *     ยังไม่ได้เปลี่ยนให้ เพราะต้องการให้โค้ดตรงกับคู่มือ
 *
 * [2] สีตัวอักษรของหน้าจอเปิดเครื่อง
 *
 *     ในคู่มือ ส่วน setup() พิมพ์ข้อความ Geiger Counter / LND712 Ready
 *     โดยไม่ได้เรียก setTextSize() และ setTextColor() ก่อน
 *     ไลบรารี SSD1306 ตั้งสีตัวอักษรเริ่มต้นเป็นสีดำ ข้อความจึงอาจไม่ปรากฏ
 *     ไฟล์นี้จึงเพิ่มสองบรรทัดนั้นเข้าไป และทำคอมเมนต์กำกับไว้แล้ว
 *
 *     (เป็นไปได้ว่าคู่มือมีสองบรรทัดนี้อยู่ แต่อยู่ตรงรอยต่อหน้าที่สแกนไม่ติด)
 *
 * [3] ปุ่มทั้งสามใช้ตัวจับเวลา debounce ร่วมกัน
 *
 *     readButton() ใช้ตัวแปร lastButtonTime ตัวเดียวกับทุกปุ่ม
 *     กดปุ่มหนึ่งแล้วอีก 200 ms ปุ่มอื่นจะกดไม่ติด
 *     เห็นชัดตอนกด Select เข้าโหมดแล้วรีบกด Up ซึ่งจะไม่ติด
 *     เป็นพฤติกรรมตามคู่มือ ไม่ได้แก้ไว้ในไฟล์นี้
 *
 * =============================================================
 * ส่วนที่ถอดความจากไฟล์สแกน โปรดตรวจทานกับคู่มือตัวจริงอีกครั้ง
 * โดยเฉพาะค่าตำแหน่งเคอร์เซอร์ใน updateDisplay() ซึ่งอ่านจากภาพ
 * ============================================================= */
