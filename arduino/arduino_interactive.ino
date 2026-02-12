const int POT1_PIN = A0;
const int BTN1_PIN = 2;

const int SENSOR_UPDATE_INTERVAL = 50;
const int DEBOUNCE_DELAY = 50;

const uint8_t START_BYTE = 0xFF;
const uint8_t SENSOR_POT1 = 0x01;
const uint8_t SENSOR_BTN1 = 0x10;

struct __attribute__((packed)) SensorData {
  uint8_t start_byte;
  uint8_t sensor_id;
  uint16_t value;
  uint8_t checksum;
};

uint8_t calculateChecksum(uint8_t sensor_id, uint16_t value) {
  return sensor_id + (value >> 8) + (value & 0xFF) & 0xFF;
}

void sendSensorData(uint8_t sensor_id, uint16_t value) {
  SensorData data = {START_BYTE, sensor_id, value, calculateChecksum(sensor_id, value)};
  Serial.write((uint8_t*)&data, sizeof(SensorData));
}

void setup() {
  Serial.begin(115200);
  pinMode(POT1_PIN, INPUT);
  pinMode(BTN1_PIN, INPUT_PULLUP);
}

void loop() {
  static unsigned long lastPotRead = 0;
  int btnState = digitalRead(BTN1_PIN);

  if (millis() - lastPotRead > SENSOR_UPDATE_INTERVAL) {
    uint16_t pot1_value = analogRead(POT1_PIN);
    sendSensorData(SENSOR_POT1, pot1_value);
    lastPotRead = millis();
  }

  static int lastBtnState = HIGH;

  if (btnState != lastBtnState) {
    sendSensorData(SENSOR_BTN1, btnState == LOW ? 1 : 0);
    lastBtnState = btnState;
    delay(DEBOUNCE_DELAY);
  }
}

