#ifndef ESP_SECRETS_H
#define ESP_SECRETS_H

// Bu dosyayi kopyalayin:  secrets.example.h -> secrets.h
// secrets.h git'e gitmez. Her iki firmware icin ayrica proje kokune de
// secrets.h kopyalayin (arduino._code.ino kok klasorden acilirsa).

#define WIFI_SSID "your_wifi_name"
#define WIFI_PASSWORD "your_wifi_password"

// Yalnizca arduino._code.ino (Firebase dogrudan ESP) icin:
#define FIREBASE_HOST "your-project-id-default-rtdb.firebaseio.com"
#define FIREBASE_AUTH "your_firebase_legacy_token_or_database_secret"

#endif
