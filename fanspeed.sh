#!/bin/bash

#This script controls the fan speed depending on the temperature

# IPMI SETTINGS FOR DELL R6xx and R7xx:

IPMIHOST={{host}}
IPMIUSER={{user}}
IPMIPW={{passwd}}
DATE=$(date +%d-%m-%Y-%H%M)

# TEMPERATURE
# Change this to the temperature in celcius you are comfortable with.
# If the temperature goes above the set degrees it will send raw IPMI command to enable dynamic fan control
MAXTEMP=44

# This variable sends a IPMI command to get the temperature, and outputs it as two digits.
# Do not edit unless you know what you do.

TEMP=`sensors | grep Core | awk '{print $3}' | sed 's/\+//g' | cut -d '.' -f 1| sort -r | head -n1`

if [[ "$TEMP" -gt "$MAXTEMP" ]];
  then
    ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW raw 0x30 0x30 0x01 0x01
    printf "*******************\nHIGH TEMPERATURE\n$DATE $TEMP\n*******************\n" >> /var/log/temperature.log
  else
    echo "$DATE $TEMP" >> /var/log/temperature.log
    ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW raw 0x30 0x30 0x01 0x00
    ipmitool -I lanplus -H $IPMIHOST -U $IPMIUSER -P $IPMIPW raw 0x30 0x30 0x02 0xff 0x1e
fi

# Send a notification to phone if temperature of server goes above 60
if [[ "$TEMP" -gt 60 ]];
  then
    curl -X POST -H "Content-Type: application/json" -d '{"value1":"Temperature of jupiter is: '$TEMP'"}' https://maker.ifttt.com/trigger/notify/with/key/{{key}}
fi
