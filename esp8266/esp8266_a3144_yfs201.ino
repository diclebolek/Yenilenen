#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ArduinoJson.h>

// WiFi / Firebase — secrets.h dosyasindan (git'e gitmez; secrets.example.h'den kopyalayin)
#include "secrets.h"

// Pin map
const uint8_t WATER_FLOW_PIN = 4;   // D2
const uint8_t HALL_GAS_PIN = 14;    // D5

// Kalibrasyon
const float GAS_M3_PER_PULSE = 0.01f;
const float WATER_PULSES_PER_LITER = 450.0f;
const int HALL_INTERRUPT_MODE = FALLING;

ESP8266WebServer server(80);

volatile uint32_t gasPulseCount = 0;
volatile uint32_t waterPulseCount = 0;

uint32_t lastGasPulseSnapshot = 0;
uint32_t lastWaterPulseSnapshot = 0;
uint32_t lastMeasureMs = 0;

float gasConsumptionM3 = 0.0f;
float waterFlowLiters = 0.0f;
float waterFlowRateLpm = 0.0f;

// --- TAKIP NOKTASI: Sensor tetiklendiginde Seri Port'a mesaj atar ---
void IRAM_ATTR onGasPulse() {
  gasPulseCount++;
}

void IRAM_ATTR onWaterPulse() {
  waterPulseCount++;
}

void connectWifi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.println("");
  Serial.print("Baglanti kuruluyor: ");
  Serial.println(WIFI_SSID);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print("."); // Baglanana kadar nokta koyar
  }

  Serial.println("");
  Serial.println("WiFi Baglandi!");
  Serial.print("IP Adresiniz: ");
  Serial.println(WiFi.localIP()); // Tarayiciya yazacagin adres
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
  Serial.println("API: Status istegi alindi.");
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
  Serial.println("API: Consumption istegi alindi.");
  computeSensorValues();

  StaticJsonDocument<384> doc;
  // Flutter tarafi ile tam uyum icin legacy alanlar da donuluyor
  doc["electricity"] = 0.0;
  doc["water"] = waterFlowLiters * 0.001; // m3
  doc["fuel"] = gasConsumptionM3;         // m3 (uyumluluk)
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
  Serial.begin(115200); // Seri port baslatildi
  delay(1000);
  Serial.println("\n--- Sistem Baslatiliyor ---");

  pinMode(HALL_GAS_PIN, INPUT_PULLUP);
  pinMode(WATER_FLOW_PIN, INPUT_PULLUP);

  attachInterrupt(digitalPinToInterrupt(HALL_GAS_PIN), onGasPulse, HALL_INTERRUPT_MODE);
  attachInterrupt(digitalPinToInterrupt(WATER_FLOW_PIN), onWaterPulse, FALLING);

  connectWifi();

  server.on("/api/status", HTTP_GET, handleStatus);
  server.on("/api/consumption", HTTP_GET, handleConsumption);
  server.begin();
  
  Serial.println("Sunucu Hazir!");
  lastMeasureMs = millis();
}

void loop() {
  // WiFi koparsa otomatik tekrar baglan
  if (WiFi.status() != WL_CONNECTED) {
    connectWifi();
  }

  computeSensorValues();
  server.handleClient();
}
