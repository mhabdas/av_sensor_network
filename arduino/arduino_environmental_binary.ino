#define SENSOR_LIGHT1 0x20
#define SENSOR_LIGHT2 0x21
#define SENSOR_TEMP1  0x30
#define SENSOR_TEMP2  0x31
#define START_BYTE 0xFF
#define BAUD_RATE 115200

void setup() {
  Serial.begin(BAUD_RATE);
}

void sendSensor(byte sensorId, int value) {
  byte high = (value >> 8) & 0xFF;
  byte low = value & 0xFF;
  byte checksum = (sensorId + high + low) & 0xFF;
  
  Serial.write(START_BYTE);
  Serial.write(sensorId);
  Serial.write(high);
  Serial.write(low);
  Serial.write(checksum);
}

void loop() {
  sendSensor(SENSOR_LIGHT1, analogRead(A0));
  sendSensor(SENSOR_LIGHT2, analogRead(A1));
  sendSensor(SENSOR_TEMP1,  analogRead(A2));
  sendSensor(SENSOR_TEMP2,  analogRead(A3));
  delay(100);
}