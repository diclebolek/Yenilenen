#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ArduinoJson.h>
#include <FirebaseESP8266.h>

// WiFi / Firebase — secrets.h (proje kokunde; secrets.example.h'den kopyalayin)
#include "secrets.h"

// Pin map
const uint8_t WATER_FLOW_PIN = 4;   // D2
const uint8_t HALL_GAS_PIN = 14;    // D5

// Kalibrasyon
const float GAS_M3_PER_PULSE = 0.01f;
const float WATER_PULSES_PER_LITER = 450.0f;
const int HALL_INTERRUPT_MODE = FALLING;

// Parazit Engelleme (Debounce) süreleri
const unsigned long WATER_DEBOUNCE_TIME = 25; 
const unsigned long GAS_DEBOUNCE_TIME = 50;

ESP8266WebServer server(80);

// Firebase nesneleri
FirebaseData firebaseData;
FirebaseAuth auth;
FirebaseConfig config;

volatile uint32_t gasPulseCount = 0;
volatile uint32_t waterPulseCount = 0;
volatile unsigned long lastWaterInterruptTime = 0;
volatile unsigned long lastGasInterruptTime = 0;

uint32_t lastGasPulseSnapshot = 0;
uint32_t lastWaterPulseSnapshot = 0;
uint32_t lastMeasureMs = 0;
uint32_t lastFirebaseSendMs = 0; 

float gasConsumptionM3 = 0.0f;
float waterFlowLiters = 0.0f;
float waterFlowRateLpm = 0.0f;

void IRAM_ATTR onGasPulse() {
  unsigned long interruptTime = millis();
  if (interruptTime - lastGasInterruptTime > GAS_DEBOUNCE_TIME) {
    gasPulseCount++;
    lastGasInterruptTime = interruptTime;
  }
}

void IRAM_ATTR onWaterPulse() {
  unsigned long interruptTime = millis();
  if (interruptTime - lastWaterInterruptTime > WATER_DEBOUNCE_TIME) {
    waterPulseCount++;
    lastWaterInterruptTime = interruptTime;
  }
}

void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  Serial.print("Baglanti kuruluyor: ");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi Baglandi!");
  Serial.print("IP Adresiniz: ");
  Serial.println(WiFi.localIP());
}

void sendDataToFirebase() {
  if (millis() - lastFirebaseSendMs > 5000) { 
    lastFirebaseSendMs = millis();
    
    // YOL DEĞİŞTİRİLDİ: /consumption/ yerine /esp8266_data/esp8266_001/latest/ yapıldı
    String path = "/esp8266_data/esp8266_001/latest";
    
    Firebase.setFloat(firebaseData, path + "/water", waterFlowLiters * 0.001); // m3 cinsinden
    Firebase.setFloat(firebaseData, path + "/fuel", gasConsumptionM3);
    Firebase.setFloat(firebaseData, path + "/water_flow_liters", waterFlowLiters);
    Firebase.setFloat(firebaseData, path + "/flow_rate_lpm", waterFlowRateLpm);
    Firebase.setInt(firebaseData, path + "/timestamp", millis());
    
    // Durum bilgisi için de yolu güncelle
    Firebase.setInt(firebaseData, "/esp8266_status/esp8266_001/uptime", millis() / 1000);
  }
}

void computeSensorValues() {
  const uint32_t now = millis();
  const uint32_t elapsedMs = now - lastMeasureMs;
  if (elapsedMs < 1000) return;

  noInterrupts();
  const uint32_t gasTotal = gasPulseCount;
  const uint32_t waterTotal = waterPulseCount;
  interrupts();

  const uint32_t gasDelta = gasTotal - lastGasPulseSnapshot;
  const uint32_t waterDelta = waterTotal - lastWaterPulseSnapshot;

  if (gasDelta > 0 || waterDelta > 0) {
    Serial.printf("Hareket Tespit Edildi! Gaz Delta: %d, Su Delta: %d\n", gasDelta, waterDelta);
  }

  gasConsumptionM3 += (gasDelta * GAS_M3_PER_PULSE);
  waterFlowLiters += (waterDelta / WATER_PULSES_PER_LITER);

  const float elapsedMinutes = elapsedMs / 60000.0f;
  waterFlowRateLpm = elapsedMinutes > 0.0f
      ? (waterDelta / WATER_PULSES_PER_LITER) / elapsedMinutes
      : 0.0f;

  lastGasPulseSnapshot = gasTotal;
  lastWaterPulseSnapshot = waterTotal;
  lastMeasureMs = now;
}

void handleStatus() {
  StaticJsonDocument<384> doc;
  doc["uptime"] = millis() / 1000;
  JsonObject wifi = doc.createNestedObject("wifi");
  wifi["ssid"] = WiFi.SSID();
  wifi["rssi"] = WiFi.RSSI();
  wifi["ip"] = WiFi.localIP().toString();
  JsonObject sensors = doc.createNestedObject("sensors");
  sensors["a3144"] = "connected";
  sensors["yf_s201"] = "connected";
  String out;
  serializeJson(doc, out);
  server.send(200, "application/json", out);
}

void handleConsumption() {
  computeSensorValues();
  StaticJsonDocument<384> doc;
  doc["electricity"] = 0.0;
  doc["water"] = waterFlowLiters * 0.001;
  doc["fuel"] = gasConsumptionM3;
  doc["waste"] = 0.0;
  doc["gas_consumption_m3"] = gasConsumptionM3;
  doc["water_flow_liters"] = waterFlowLiters;
  doc["flow_rate_lpm"] = waterFlowRateLpm;
  doc["timestamp"] = millis();
  String out;
  serializeJson(doc, out);
  server.send(200, "application/json", out);
}

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n--- Sistem Baslatiliyor ---");

  pinMode(HALL_GAS_PIN, INPUT_PULLUP);
  pinMode(WATER_FLOW_PIN, INPUT_PULLUP);

  attachInterrupt(digitalPinToInterrupt(HALL_GAS_PIN), onGasPulse, HALL_INTERRUPT_MODE);
  attachInterrupt(digitalPinToInterrupt(WATER_FLOW_PIN), onWaterPulse, FALLING);

  connectWifi();

  // Firebase Yapilandirmasi
  config.host = FIREBASE_HOST;
  config.signer.tokens.legacy_token = FIREBASE_AUTH;
  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);

  server.on("/api/status", HTTP_GET, handleStatus);
  server.on("/api/consumption", HTTP_GET, handleConsumption);
  server.begin();
  
  Serial.println("Sunucu ve Firebase Hazir!");
  lastMeasureMs = millis();
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    connectWifi();
  }

  computeSensorValues();
  sendDataToFirebase(); 
  server.handleClient();
}
