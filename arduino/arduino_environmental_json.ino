#define BAUD_RATE 115200

void setup() {
  Serial.begin(BAUD_RATE);
}

void sendSensor(const char* name, int value) {
  Serial.print("{\"sensor\":\"");
  Serial.print(name);
  Serial.print("\",\"value\":");
  Serial.print(value);
  Serial.println("}");
}

void loop() {
  sendSensor("LIGHT1", analogRead(A0));
  sendSensor("LIGHT2", analogRead(A1));
  sendSensor("TEMP1",  analogRead(A2));
  sendSensor("TEMP2",  analogRead(A3));
  delay(100);
}