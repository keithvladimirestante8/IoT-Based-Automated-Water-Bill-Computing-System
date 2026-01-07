#include <Wire.h>
#include <DS3231.h>
#include <LiquidCrystal_I2C.h>
#include <ESP8266WiFi.h>
#include <FirebaseESP8266.h>
#include <FS.h>
#include <LittleFS.h>
#include <WiFiManager.h>
#include <time.h>


#define FIREBASE_HOST "water-bill-system-89865-default-rtdb.asia-southeast1.firebasedatabase.app"
#define FIREBASE_AUTH "IOfUTmN7WiDYRMViqgO5zZ61WwyCZcpMt7mAlLZL"

FirebaseData firebaseData;
FirebaseAuth auth;
FirebaseConfig config;

DS3231 rtc;
LiquidCrystal_I2C lcd(0x27, 16, 2);

int flowSensorPin = D5;
volatile int pulseCount = 0;
float flowRate = 0.0;


float totalWater = 0.0;
float currentBill = 0.0;


float hourlyUsage = 0.0;
int hourlyEntries = 0;


float tier1Price = 0.0255;
float tier2Price = 0.0270;
float tier3Price = 0.0300;
float waterLimit = 30000.0; 

unsigned long lastPollTime = 0;
unsigned long pollInterval = 1000;
unsigned long lastFlowDetectedTime = 0;
bool showingFlow = false;

unsigned long lastHeartbeat = 0; 

String prevDisplayedLine1 = "";
String prevDisplayedLine2 = "";

int buzzerPin = D3;
float calibrationFactor = 52.47;
const String userID = "ny8myOZnypSxTEtqfGzSLsSpvK23";
bool hasBuzzed = false;

#define LOG_FILENAME "/water_logs.dat"
#define MAX_LOGS_LITTLEFS 1000
int littlefsLogCount = 0;
bool pendingLittleFSLogs = false;

int lastUploadedHour = -1;

struct LogEntry {
  uint16_t year;
  uint8_t month;
  uint8_t day;
  uint8_t hour;
  uint8_t minute;
  uint8_t second;
  float waterUsage;
  float bill;
};

String getMonthName(int m) {
  const char* months[] = {"January", "February", "March", "April", "May", "June",
                          "July", "August", "September", "October", "November", "December"};
  if(m < 1 || m > 12) return "Unknown";
  return months[m - 1];
}


void saveTotalsToLittleFS() {

  if (totalWater < 0 || currentBill < 0) return;

  if (!LittleFS.begin()) return;
  File f = LittleFS.open("/totals.dat", "w");
  if (!f) { LittleFS.end(); return; }
  f.print(totalWater, 6); f.print(" ");
  f.print(currentBill, 6); f.print(" ");
  f.print(hasBuzzed ? 1 : 0); f.println();
  f.close();
  LittleFS.end();
}

void loadTotalsFromLittleFS() {
  if (!LittleFS.begin()) return;
  if (!LittleFS.exists("/totals.dat")) { LittleFS.end(); return; }
  File f = LittleFS.open("/totals.dat", "r");
  if (!f) { LittleFS.end(); return; }
  totalWater = f.parseFloat();
  currentBill = f.parseFloat();
  hasBuzzed = (f.parseInt() != 0);
  f.close();
  LittleFS.end();
}


void checkMonthReset(int currentMonth, int currentYear) {

  if (currentYear < 2025) return;

  if (!LittleFS.begin()) return;
  File file = LittleFS.open("/month_reset.dat", "r");
  int storedMonth = 0, storedYear = 0;
  if (file) { storedMonth = file.parseInt(); storedYear = file.parseInt(); file.close(); }
  
  if (storedMonth != currentMonth || storedYear != currentYear) {
    file = LittleFS.open("/month_reset.dat", "w");
    if (!file) { LittleFS.end(); return; }
    file.print(currentMonth); file.print(" "); file.print(currentYear); file.close();
    

    Firebase.setFloat(firebaseData, "/Users/" + userID + "/Summary/Water_Usage", 0.0);
    Firebase.setFloat(firebaseData, "/Users/" + userID + "/Summary/Total_Bill", 0.0);
    Firebase.setString(firebaseData, "/Users/" + userID + "/Summary/Display_Total_Bill", "₱0.00");
    
    totalWater = 0.0; currentBill = 0.0; littlefsLogCount = 0; hasBuzzed = false;
    
    if (LittleFS.exists("/totals.dat")) LittleFS.remove("/totals.dat");
  }
  LittleFS.end();
}

void createPreviousMonthFolder() {
  bool Century;
  int currentMonth = rtc.getMonth(Century);
  int currentYear = rtc.getYear();
  
  if (currentYear < 2025) return;

  int prevMonth = currentMonth - 1;
  if (prevMonth == 0) { prevMonth = 12; currentYear--; }
  String prevMonthName = getMonthName(prevMonth);
  String prevYear = String(currentYear);
  String path = "/Users/" + userID + "/Water_Logs/" + prevYear + "/" + prevMonthName;
  Firebase.setString(firebaseData, path + "/.info", "archive");
}


void syncPrices() {
  if (WiFi.status() == WL_CONNECTED) {
    if (Firebase.getFloat(firebaseData, "/Users/" + userID + "/Settings/Prices/Tier1")) tier1Price = firebaseData.floatData();
    if (Firebase.getFloat(firebaseData, "/Users/" + userID + "/Settings/Prices/Tier2")) tier2Price = firebaseData.floatData();
    if (Firebase.getFloat(firebaseData, "/Users/" + userID + "/Settings/Prices/Tier3")) tier3Price = firebaseData.floatData();
    
    if (Firebase.getFloat(firebaseData, "/Users/" + userID + "/Settings/Water_Limit")) {
        float fetchedLimit = firebaseData.floatData();
        if (fetchedLimit > 0) waterLimit = fetchedLimit;
    }
  }
}

float calculateBillForUsage(float usageAmount, float currentTotal) {
  float rate = tier1Price;
  if (currentTotal > 200) rate = tier3Price;
  else if (currentTotal > 100) rate = tier2Price;
  return usageAmount * rate;
}


void saveLogToLittleFS(uint16_t year, uint8_t month, uint8_t day, uint8_t hour, uint8_t min, uint8_t sec, float water, float bill) {
  if (!LittleFS.begin()) return;
  if (littlefsLogCount < MAX_LOGS_LITTLEFS) {
    File file = LittleFS.open(LOG_FILENAME, "a");
    if (!file) { LittleFS.end(); return; }
    
    LogEntry entry;
    entry.year = year;
    entry.month = month;
    entry.day = day;
    entry.hour = hour;
    entry.minute = min;
    entry.second = sec;
    entry.waterUsage = water;
    entry.bill = bill;

    file.write((const byte*)&entry, sizeof(LogEntry));
    file.close();
    
    littlefsLogCount++; pendingLittleFSLogs = true;
    File countFile = LittleFS.open("/log_count.dat", "w");
    if (countFile) { countFile.print(littlefsLogCount); countFile.close(); }
  }
  LittleFS.end();
}

void uploadLogsFromLittleFS() {
  if (!pendingLittleFSLogs) return;
  if (!LittleFS.begin()) return;
  int totalLogs = 0;
  File countFile = LittleFS.open("/log_count.dat", "r");
  if (countFile) { totalLogs = littlefsLogCount = countFile.parseInt(); countFile.close(); }
  if (totalLogs == 0) { LittleFS.end(); pendingLittleFSLogs = false; return; }

  File file = LittleFS.open(LOG_FILENAME, "r");
  if (!file) { LittleFS.end(); return; }

  for (int i = 0; i < totalLogs; i++) {
    LogEntry log;
    char buffer[sizeof(LogEntry)];
    if (file.readBytes(buffer, sizeof(LogEntry)) != sizeof(LogEntry)) { break; }
    memcpy(&log, buffer, sizeof(LogEntry));

    char timestampStr[35];
    sprintf(timestampStr, "%04d-%02d-%02d_%02d-%02d-%02d", 
            2000 + log.year, log.month, log.day, log.hour, log.minute, log.second);
    
    String monthName = getMonthName(log.month);
    String yearStr = String(2000 + log.year);
    String basePath = "/Users/" + userID + "/Water_Logs/" + yearStr + "/" + monthName + "/" + String(timestampStr);

    if (!Firebase.setFloat(firebaseData, basePath + "/Water_Usage", log.waterUsage)) break;
    if (!Firebase.setFloat(firebaseData, basePath + "/Bill", log.bill)) break;
    Firebase.setFloat(firebaseData, basePath + "/TotalUsage", log.waterUsage); 
    if (!Firebase.setString(firebaseData, basePath + "/Display_Bill", "₱" + String(log.bill, 2))) break;
  }

  file.close();
  LittleFS.remove(LOG_FILENAME); littlefsLogCount = 0;
  File countFile2 = LittleFS.open("/log_count.dat", "w"); if (countFile2) { countFile2.print(littlefsLogCount); countFile2.close(); }
  pendingLittleFSLogs = false;
  LittleFS.end();
}


void setup() {
  Serial.begin(115200);
  Wire.begin(D1, D2);
  lcd.begin(16, 2); lcd.backlight();
  pinMode(flowSensorPin, INPUT_PULLUP);
  pinMode(buzzerPin, OUTPUT);

  if (!LittleFS.begin()) Serial.println("LittleFS init failed!");
  

  File countFile = LittleFS.open("/log_count.dat", "r"); 
  if (countFile) { littlefsLogCount = countFile.parseInt(); countFile.close(); }
  loadTotalsFromLittleFS();


  if (totalWater < 0 || isnan(totalWater)) {
     Serial.println("Local Memory Corrupt. Resetting temp to 0.");
     totalWater = 0.0;
  }
  if (currentBill < 0 || isnan(currentBill)) {
     currentBill = 0.0;
  }

  WiFiManager wifiManager;
  wifiManager.autoConnect("Water Billing Wi-Fi");
  
  config.host = FIREBASE_HOST;
  auth.user.email = ""; auth.user.password = "";
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  

  if (WiFi.status() == WL_CONNECTED) {
      syncPrices(); 


      if (Firebase.getFloat(firebaseData, "/Users/" + userID + "/Summary/Water_Usage")) {
          float cloudWater = firebaseData.floatData();
          

          if (cloudWater > totalWater && cloudWater > 0 && !isnan(cloudWater)) {
              totalWater = cloudWater;
              Serial.print("Data Restored from Cloud: "); Serial.println(totalWater);
          }
      }
      

      if (Firebase.getFloat(firebaseData, "/Users/" + userID + "/Summary/Total_Bill")) {
          float cloudBill = firebaseData.floatData();
          if (cloudBill > currentBill && cloudBill > 0 && !isnan(cloudBill)) {
              currentBill = cloudBill;
          }
      }

      if (totalWater > 0) saveTotalsToLittleFS();
  }

  bool Century;
  int currentMonth = rtc.getMonth(Century);
  int currentYear = rtc.getYear();
  

  if (currentYear > 2024) {
      checkMonthReset(currentMonth, currentYear);
  }
  createPreviousMonthFolder();

  bool h12flag, pmflag;
  lastUploadedHour = rtc.getHour(h12flag, pmflag);
}


void flushHourlyData() {
  if (hourlyUsage <= 0) return;


  if (totalWater <= 0 || currentBill <= 0) {
      return; 
  }

  syncPrices();

  float billForThisHour = calculateBillForUsage(hourlyUsage, totalWater);

  Firebase.setFloat(firebaseData, "/Users/" + userID + "/Summary/Water_Usage", totalWater);
  Firebase.setFloat(firebaseData, "/Users/" + userID + "/Summary/Total_Bill", currentBill);
  Firebase.setString(firebaseData, "/Users/" + userID + "/Summary/Display_Total_Bill", "₱" + String(currentBill, 2));

  bool h12, PM, Century;
  saveLogToLittleFS(
    rtc.getYear(), 
    rtc.getMonth(Century), 
    rtc.getDate(), 
    rtc.getHour(h12, PM), 
    rtc.getMinute(), 
    rtc.getSecond(), 
    hourlyUsage, 
    billForThisHour
  );
  
  if (WiFi.status() == WL_CONNECTED) {
    uploadLogsFromLittleFS();
  }

  hourlyUsage = 0.0;
  hourlyEntries = 0;
}


void loop() {
  unsigned long currentMillis = millis();
  unsigned long pulseDuration = pulseIn(flowSensorPin, LOW, 100000);
  if (pulseDuration > 0) { pulseCount++; lastFlowDetectedTime = currentMillis; showingFlow = true; }

  bool h12, PM, Century;
  int hr = rtc.getHour(h12, PM), min = rtc.getMinute(), sec = rtc.getSecond();
  int day = rtc.getDate(), month = rtc.getMonth(Century), year = rtc.getYear();

  checkMonthReset(month, year);

  if (WiFi.status() == WL_CONNECTED && currentMillis - lastHeartbeat > 5000) {
    lastHeartbeat = currentMillis;
    Firebase.setTimestamp(firebaseData, "/Users/" + userID + "/Device_Status/last_seen");
    syncPrices(); 
  }

  if (currentMillis - lastPollTime >= pollInterval) {
    lastPollTime = currentMillis;
    if (pulseCount > 0) {
      flowRate = ((pulseCount / 450.0) * 0.2857) * calibrationFactor;
      pulseCount = 0; 
      
      totalWater += flowRate; 
      hourlyUsage += flowRate;
      hourlyEntries++;
      
      if (totalWater <= 100) currentBill = totalWater * tier1Price;
      else if (totalWater <= 200) currentBill = 100 * tier1Price + (totalWater - 100) * tier2Price;
      else currentBill = 100 * tier1Price + 100 * tier2Price + (totalWater - 200) * tier3Price;
      
      saveTotalsToLittleFS();
    }

    String line1 = "", line2 = "";
    if (showingFlow) {
      line1 = "Water: " + String(totalWater, 2) + " L";
      line2 = "Bill: " + String(currentBill, 2);
      if (currentMillis - lastFlowDetectedTime > 5000) showingFlow = false;
    } else {
      line1 = "Date: " + String(day) + "/" + String(month) + "/" + String(year);
      line2 = "Time: " + String(hr) + ":" + (min < 10 ? "0" : "") + String(min) + ":" + (sec < 10 ? "0" : "") + String(sec);
    }

    if (line1 != prevDisplayedLine1 || line2 != prevDisplayedLine2) {
      lcd.clear(); lcd.setCursor(0, 0); lcd.print(line1); lcd.setCursor(0, 1); lcd.print(line2);
      prevDisplayedLine1 = line1; prevDisplayedLine2 = line2;
    }
  }

  if (totalWater > waterLimit && !hasBuzzed) {
    digitalWrite(buzzerPin, HIGH); delay(1000); digitalWrite(buzzerPin, LOW);
    hasBuzzed = true; saveTotalsToLittleFS();
  }

  int currentHour = rtc.getHour(h12, PM);
  if (currentHour != lastUploadedHour) {
    flushHourlyData(); 
    lastUploadedHour = currentHour;
  }

  static unsigned long lastSmartSave = 0;
  if (millis() - lastSmartSave > 30000) {
    float tempBill = calculateBillForUsage(hourlyUsage, totalWater);
    if (hourlyUsage > 0 && tempBill >= 0.01) {
        flushHourlyData(); 
        lastSmartSave = millis();
    }
  }

  if (WiFi.status() == WL_CONNECTED) uploadLogsFromLittleFS();

  delay(200);
}