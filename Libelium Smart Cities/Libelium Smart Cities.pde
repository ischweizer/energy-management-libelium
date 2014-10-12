#include <Wasp3G.h>
#include <WaspSensorCities.h>



//communication
char aux_str[1000];
char args[600];
char* url = "/test/api.php";
char* host = "www.da-sense.de";
char* username = "forproj14";
char* sha1pw = "a2d1d7540c6919c15744902899c9d21496666cef";
char* md5pw = "200b6e70991f194e7dac0e481ee3c90e";
int8_t answer;
char* phpSessionID;
char serialIDasString[10];
unsigned long id;
char hashedSerialID[40];

//sensor readings
int sampleNum = 0;
int GPSnum = 0;
float temperature;float dust = 0.0;
float noise = 0.0;
float humidity = 0;
char longlat[6][20];
char values[12][6];
char temp[6];

//energy management
int batteryLevel;
int batteryLevels[12];
int batteryCount;
float decreasingFactor = 0.5;
float increasingFactor = 1.1;
long timeSinceLastBatterySample = 0;
int batteryThreshold = 0;
boolean enoughEnergy = true;
int GPStries = 0;
char* deepsleepTime = "00:00:01:00"; //1 hour
// real values
long samplingRate = 3600000; 
long dayInMilliSeconds = 43200000; //actually half a day for the time being
//values for testing
//long samplingRate = 600000; //10min
//long dayInMilliSeconds = 3600000;

//parameters for the file
char* filename = "BOT.TXT";
char dataToAppend[100]; 
char* timestamp;
uint8_t sdAnswer;

void setup() {
    USB.ON();
    RTC.ON();
    SensorCities.ON();
    
    //turn on the 3G module
    answer = _3G.ON();
    if ((answer == 1) || (answer == -3)) {
      USB.println(F("3G module started"));     
      answer = _3G.startGPS();
      if(answer == 1) {
        USB.println(F("GPS started"));
      } else {
        USB.println(F("GPS not started"));
      }
    } else {
      USB.println(F("3G module not started"));
   }
   
   //set SD on and create file
   SD.ON();
   sdAnswer = SD.create(filename);
   if(sdAnswer == 1){
     USB.println(F("File created"));
     SD.appendln(filename, RTC.getTime());
   } else {
     USB.println(F("File not created"));
     USB.println(F("************************ File Content ************************"));
     SD.showFile(filename);
     USB.println(F("**************************************************************"));
     SD.appendln(filename, "FILE ALREADY EXISTS : NEW CONTENT");
   }
   
  //deepsleepTime = samplingRateToWaitingTime(samplingRate);
  }


void loop() {
    //read battery level in percent and convert it into a string
    SD.ON();
    _3G.ON();
    RTC.ON();
    SensorCities.ON();
    
    PWR.getBatteryLevel();
    batteryLevel = PWR.getBatteryLevel();
    batteryLevels[batteryCount] = batteryLevel;
    batteryCount++;
    if(batteryCount == 12) {
      batteryCount = 0;
    }
    USB.print(F("Batterylevel: "));
    USB.println(batteryLevel);
    timestamp = RTC.getTime();
    sprintf(dataToAppend, "%s, batterylevel: %d, Samplingrate: %ld%n", timestamp, batteryLevel, samplingRate);
    
    //write battery level in the file
    sdAnswer = SD.appendln(filename, dataToAppend);
    if(sdAnswer == 1){
     USB.println(F("************************ File Content ************************"));
     SD.showFile(filename);
     USB.println(F("**************************************************************"));
    } else {
      USB.println(F("Could not append to the file."));
      USB.println(sdAnswer);
    }
    
    //check if an update of the samplingRate is necessary
    if(timeSinceLastBatterySample >= dayInMilliSeconds) {
      //check if there is an increase or decrease in the level of the battery over the last 12 batterysamples
      int avgBattery = 0;
      int c = 0;
      for(int x = 0; x < 12; x++) {
        avgBattery += batteryLevels[x];
          if(batteryLevels[x] != 0) {
            c++;
          }        
      }
      avgBattery = avgBattery / c;
      batteryCount = 0;
      if((batteryLevel - avgBattery) >= 0) {
        //increase
        enoughEnergy = true;
      } else {
        //decrease
        enoughEnergy = false;
      }
      
      samplingRate = adaptSamplingRate();
      deepsleepTime = millisecondsToDeepSleepTime();
      
      timeSinceLastBatterySample = 0;
    }
    
    timeSinceLastBatterySample += samplingRate;
    
    if(getGPS()) {
    
      readSensors();
    
      USB.println(sampleNum, DEC);
      //wait until you have done 4 samples, then try to send them
      if(batteryLevel > batteryThreshold && sampleNum > 15) {
        sendSamples();
        sampleNum = 0;
        GPSnum = 0;
      }
      delay(60000);
      //wait to do next sampling
      USB.println("Entering deepsleep mode");
      PWR.deepSleep(deepsleepTime, RTC_OFFSET, RTC_ALM1_MODE1, ALL_OFF);
    
      if(intFlag & RTC_INT) {
        intFlag &= ~(RTC_INT);
        USB.println(F("Wake up"));
      }
    }
    else if (GPStries < 4){
      //If you have no GPS wait for 30 seconds and try again
      delay(30000);
      GPStries++;
    } else {
      PWR.deepSleep(deepsleepTime, RTC_OFFSET, RTC_ALM1_MODE1, ALL_OFF);
    
      if(intFlag & RTC_INT) {
        intFlag &= ~(RTC_INT);
        USB.println(F("Wake up"));
      }
    }
  }



void sendSamples() {
    _3G.setPIN("6358");
    answer = _3G.check(60);
        if (answer == 1) {
              //print values:
              USB.print(F("Gemessene Werte: "));
              for(int j = 0; j < 12; j++) {
                USB.print(j, DEC);
                USB.print(F(": "));
                USB.println(values[j]);
              }
              //4 samples of the same type in 1 call and for every sample you need to re-authenticate yourself with the server
              for(int i = 0; i < 3; i++) {
                sprintf(args, "call=account&action=login&compatibility=1&username=%s&password_sha=%s&password_md5=%s&locale=deDE&deviceinfo={\"deviceType\":2,\"deviceIdent\":\"%lu\",\"deviceManufactor\":\"libelium\",\"deviceModel\":\"plugAndSense\",\"deviceName\":\"SmartCities\",\"sensors\":[{\"measurementType\":1},{\"measurementType\":4},{\"measurementType\":6},{\"measurementType\":8}]}", username, sha1pw, md5pw, Utils.readSerialID());
                USB.print(F("args content: "));
                USB.println(args);
                USB.print(F("args content length: "));
                USB.println(strlen(args), DEC);
                sprintf(aux_str, "POST %s? HTTP/1.1\r\nHost: %s\r\nContent-Type: application/x-www-form-urlencoded; charset=UTF-8\r\nContent-Length: %d\r\n\r\n%s", url, host, strlen(args), args);
                USB.print(F("HTTP-request content: "));
                USB.println(aux_str);
                USB.print(F("HTTP-request content length: "));
                USB.println(strlen(aux_str), DEC);
            
                answer = _3G.readURL(host, 80, aux_str);
            
                //Self implemented method in the _3G library, not standard
                phpSessionID = _3G.getSessionID();
            
                //reset the char arrays back to empty
                aux_str[0]='\0';
                args[0]='\0';
                delay(5000);
                
                if(strlen(phpSessionID) > 0) {
                  int measurementType = 0;
                  if(i == 0) {
                    //temperature
                    measurementType = 4;
                  }
                  if(i == 1) {
                    //humidity
                    measurementType = 6;
                  }
                  if(i == 2) {
                    //noise
                    measurementType = 1;
                  }
                  if(i == 3) {
                    //dust
                    measurementType = 8;
                  }
                  sprintf(args, "call=input&type=data&json={\"deviceIdent\":\"%lu\",\"measurementType\":%d,\"series\":[{\"name\":\"testSensornode\",\"visibility\":1,\"timestamp\":1,\"values\":[{\"timestamp\":1,\"value\":%s,\"longitude\":%s,\"latitude\":%s,\"altitude\":0,\"accuracy\":0,\"provider\":\"GPS\"},{\"timestamp\":1,\"value\":%s,\"longitude\":%s,\"latitude\":%s,\"altitude\":0,\"accuracy\":0,\"provider\":\"GPS\"},{\"timestamp\":1,\"value\":%s,\"longitude\":%s,\"latitude\":%s,\"altitude\":0,\"accuracy\":0,\"provider\":\"GPS\"}]}]}", Utils.readSerialID(), measurementType, values[i], longlat[0], longlat[1], values[i+4], longlat[2], longlat[3], values[i+8], longlat[4], longlat[5]);              
                  USB.print(F("args content: "));
                  USB.println(args);
                  USB.print(F("args content length: "));
                  USB.println(strlen(args), DEC);
                  sprintf(aux_str, "POST %s? HTTP/1.1\r\nHost: %s\r\nContent-Type: application/x-www-form-urlencoded; charset=UTF-8\r\nContent-Length: %d\r\nCookie: PHPSESSID=%s\r\n\r\n%s", url, host, strlen(args), phpSessionID, args);
                  USB.print(F("HTTP-request content: "));
                  USB.println(aux_str);
                  USB.print(F("HTTP-request content length: "));
                  USB.println(strlen(aux_str), DEC);
              
                  answer = _3G.readURL(host, 80, aux_str);
      
                  //reset the char arrays back to empty
                  aux_str[0]='\0';
                  args[0]='\0';
                  //small delay between the uploads
                  delay(1000);
              } else {
              SD.appendln(filename, "Could not authenticate with server");
              }
            }
        }
}

void readSensors() {
  SensorCities.setSensorMode(SENS_ON, SENS_CITIES_TEMPERATURE);
  delay(100);
  temperature = SensorCities.readValue(SENS_CITIES_TEMPERATURE);
  SensorCities.setSensorMode(SENS_OFF, SENS_CITIES_TEMPERATURE);
  Utils.float2String(temperature, temp, 2);
  strcpy(values[sampleNum], temp);
  sampleNum++;  

  SensorCities.setSensorMode(SENS_ON, SENS_CITIES_HUMIDITY);
  delay(100);
  humidity = SensorCities.readValue(SENS_CITIES_HUMIDITY);
  SensorCities.setSensorMode(SENS_OFF, SENS_CITIES_HUMIDITY);
  Utils.float2String(humidity, temp, 2);
  strcpy(values[sampleNum], temp);
  sampleNum++;
  
  SensorCities.setSensorMode(SENS_ON, SENS_CITIES_AUDIO);
  delay(100);
  noise = SensorCities.readValue(SENS_CITIES_AUDIO);
  SensorCities.setSensorMode(SENS_OFF, SENS_CITIES_AUDIO);
  Utils.float2String(noise, temp, 2);
  strcpy(values[sampleNum], temp);
  sampleNum++;
  
  SensorCities.setSensorMode(SENS_ON, SENS_CITIES_DUST);
  delay(100);
  dust = SensorCities.readValue(SENS_CITIES_DUST);
  SensorCities.setSensorMode(SENS_OFF, SENS_CITIES_DUST);
  Utils.float2String(dust, temp, 2);
  strcpy(values[sampleNum], temp);
  sampleNum++;
}


//get GPS information via 3G, convert it to char-array and save it to longlat-array
boolean getGPS() {
  uint8_t gpsAnswer = _3G.startGPS();
  //accuracy not available via 3G modul
  char latitude[20];
  char longitude[20];
  if(gpsAnswer == 1) {
    Utils.float2String(_3G.convert2Degrees(_3G.latitude), latitude, 10);    
    Utils.float2String(_3G.convert2Degrees(_3G.longitude), longitude, 10);
    strcpy(longlat[GPSnum], longitude);
    GPSnum++;
    strcpy(longlat[GPSnum], latitude);
    GPSnum++;
    return true;
  } else {
    SD.appendln(filename, "No GPS available");
    return false;
  }
}

long adaptSamplingRate() {
  int oldSamplingRate;
  long nSamplingRate;
  if(enoughEnergy){
    nSamplingRate = (int) (samplingRate * increasingFactor);
  } else {
    nSamplingRate = (int) (samplingRate * decreasingFactor);
  }
  return nSamplingRate;
}


//does not work properly, the calculation-results for hours, minutes and seconds are bullshit
char* millisecondsToDeepSleepTime() {
  char waitingTime[18];
  char h[4];
  char m[4];
  char s[4];
  unsigned long hours =  0;
  hours = (samplingRate / 1000);
  hours = hours / 3600;
  hours = hours % 24;
  unsigned long minutes = 0;
  minutes = samplingRate / 1000;
  minutes = minutes / 60;
  minutes = minutes % 60;
  unsigned long seconds = 0;
  seconds = (samplingRate / 1000);
  seconds = seconds % 60;
  
  if(hours < 10) {
    snprintf(h, 4, "0%d", hours);
  } else {
    snprintf(h, 4, "%d", hours);
  }
  if(minutes < 10) {
    snprintf(m, 4, "0%d", minutes);
  } else {
    snprintf(m, 4, "%d", minutes);
  }
  if(seconds < 10) {
    snprintf(s, 4, "0%d", seconds);
  } else {
    snprintf(s, 4, "%d", seconds);
  }
  
  snprintf(waitingTime, 18, "00:%s:%s:%s", h, m, s);
  USB.print(F("WaitingTime = "));
  USB.println(waitingTime);
  return waitingTime;
}

