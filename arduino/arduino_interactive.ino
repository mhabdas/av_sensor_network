const int SENSOR_UPDATE_INTERVAL = 50;
const int DEBOUNCE_DELAY = 50;

const uint8_t START_BYTE = 0xFF;

struct __attribute__((packed)) SensorData {
  uint8_t start_byte;
  uint8_t sensor_id;
  uint16_t value;
  uint8_t checksum;
};

struct SensorConfig {
  int pin;
  uint8_t sensor_id;
};

const SensorConfig POTS[] = {{A0, 0x01}, {A1, 0x02}};
const SensorConfig BTNS[] = {{2, 0x10}, {4, 0x11}, {7, 0x12}};
const int NUM_POTS = sizeof(POTS) / sizeof(POTS[0]);
const int NUM_BTNS = sizeof(BTNS) / sizeof(BTNS[0]);

uint8_t calculateChecksum(uint8_t sensor_id, uint16_t value) {
  return (sensor_id + (value >> 8) + (value & 0xFF)) & 0xFF;
}

void sendSensorData(uint8_t sensor_id, uint16_t value) {
  SensorData data = {START_BYTE, sensor_id, value, calculateChecksum(sensor_id, value)};
  Serial.write((uint8_t*)&data, sizeof(SensorData));
}

void setup() {
  Serial.begin(115200);
  for (int i = 0; i < NUM_POTS; i++) pinMode(POTS[i].pin, INPUT);
  for (int i = 0; i < NUM_BTNS; i++) pinMode(BTNS[i].pin, INPUT_PULLUP);
}

void loop() {
  static unsigned long lastPotRead = 0;
  static int lastBtnStates[NUM_BTNS] = {HIGH, HIGH, HIGH};

  if (millis() - lastPotRead > SENSOR_UPDATE_INTERVAL) {
    for (int i = 0; i < NUM_POTS; i++) {
      sendSensorData(POTS[i].sensor_id, analogRead(POTS[i].pin));
    }
    lastPotRead = millis();
  }

  for (int i = 0; i < NUM_BTNS; i++) {
    int state = digitalRead(BTNS[i].pin);
    if (state != lastBtnStates[i]) {
      sendSensorData(BTNS[i].sensor_id, state == LOW ? 1 : 0);
      lastBtnStates[i] = state;
      delay(DEBOUNCE_DELAY);
    }
  }
}
