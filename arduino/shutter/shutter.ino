#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

#define LED_PIN 2

BLECharacteristic *pCharacteristic;

class MyCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pChar) {
        String value = pChar->getValue();
        if (value.length() > 0) {
            if (value[0] == '1') {
                digitalWrite(LED_PIN, HIGH);
            } else if (value[0] == '0') {
                digitalWrite(LED_PIN, LOW);
            }
        }
    }
};

void setup() {
    pinMode(LED_PIN, OUTPUT);
    
    BLEDevice::init("ESP32_LED");
    BLEServer *pServer = BLEDevice::createServer();
    BLEService *pService = pServer->createService("12345678-1234-1234-1234-123456789abc");
    
    pCharacteristic = pService->createCharacteristic(
        "abcd1234-ab12-cd34-ef56-123456789abc",
        BLECharacteristic::PROPERTY_WRITE
    );
    pCharacteristic->setCallbacks(new MyCallbacks());
    
    pService->start();
    pServer->getAdvertising()->start();
}

void loop() {
    delay(100);
}