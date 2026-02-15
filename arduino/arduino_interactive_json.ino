const int SENSOR_UPDATE_INTERVAL = 50;
const int DEBOUNCE_DELAY = 50;

struct SensorConfig {
  int pin;
  const char* name;
};

const SensorConfig POTS[] = {{A0, "POT1"}, {A1, "POT2"}};
const SensorConfig BTNS[] = {{2, "BTN1"}, {4, "BTN2"}, {7, "BTN3"}};
const int NUM_POTS = sizeof(POTS) / sizeof(POTS[0]);
const int NUM_BTNS = sizeof(BTNS) / sizeof(BTNS[0]);

void sendSensorData(const char* sensor, uint16_t value) {
  Serial.print("{\"sensor\":\"");
  Serial.print(sensor);
  Serial.print("\",\"value\":");
  Serial.print(value);
  Serial.println("}");
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
      sendSensorData(POTS[i].name, analogRead(POTS[i].pin));
    }
    lastPotRead = millis();
  }

  for (int i = 0; i < NUM_BTNS; i++) {
    int state = digitalRead(BTNS[i].pin);
    if (state != lastBtnStates[i]) {
      sendSensorData(BTNS[i].name, state == LOW ? 1 : 0);
      lastBtnStates[i] = state;
      delay(DEBOUNCE_DELAY);
    }
  }
}
