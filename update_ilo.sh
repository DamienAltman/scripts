#!/bin/bash

#This script will configure the correct timezone for the HPE ilos and set the option for using dhcp supplied NTP servers
#change the TZCODE for your location
#
CMTOOL_ROOT="/root/cm-tool"
NETRCFILE=
OFFLINE_NODES="${CMTOOL_ROOT}/.pdsherrorcm-ilo.txt"
ILO_DOMAIN=""

TZCODE="xx"

if [ "$#" -lt 1 ]
then
	echo "Usage:"
	echo "  ./script.sh nodes[1-9]"
	echo ""
	echo "To make no change and simply check the ntp and timezone settings:"
	echo "  ./script.sh nodes[1-9] check"
	echo ""
	exit 1
fi



range=$1

declare -a nodes

#change the range notation from node[1-5] to node{1..5} which bash can interpret
nodes=( $(eval echo $(echo "${range}" | sed -E 's:\[(.*)\]:{\1}:;s:([0-9]+)-([0-9]+):{\1..\2}:g;s:^\{([^,]*)\}$:\1:') | tr -d {}) )

#array length for testing
alen=${#nodes[@]}

nodesOffline () {
    errorOut=$(cat $OFFLINE_NODES | grep "^pdsh" | awk '{ print $2 }')
    if [ -s $OFFLINE_NODES ]
    then
      echo ""
      echo "WARNING - THESE NODES ARE UNREACHABLE"
      echo "$errorOut" |tr -d ':'
      echo ""
    fi
}

#Disable NTP option in iLO as setting the timezone is not possible otherwise
disable_ntp () {

	pdsh -f 24 -R exec -w $range curl --netrc-file $NETRCFILE -H "Content-Type: application/json" -X PATCH https://%h${ILO_DOMAIN}/redfish/v1/Managers/1/EthernetInterfaces/1/ --insecure  -s -w '\n' -m 5 -d \
'{
 "Oem": {
   "Hpe": {
     "DHCPv4": {
        "ClientIdType": "Default",
        "Enabled": true,
        "UseDNSServers": true,
        "UseDomainName": true,
        "UseGateway": false,
        "UseNTPServers": false,
        "UseStaticRoutes": false,
        "UseWINSServers": false
      },
     "DHCPv6": {
        "StatefulModeEnabled": false,
        "StatelessModeEnabled": false,
        "UseDNSServers": false,
        "UseDomainName": false,
        "UseNTPServers": false,
        "UseRapidCommit": false
      }
    }
  }
}' 2> $OFFLINE_NODES

	nodesOffline
}

set_tz () {
	pdsh -f 24 -R exec -w $range curl --netrc-file $NETRCFILE -H "Content-Type: application/json" -X PATCH https://%h${ILO_DOMAIN}/redfish/v1/Managers/1/DateTime/ --insecure  -s -w '\n' -m 5 -d \
"{
	\"TimeZone\": {
	        \"Index\": ${TZCODE}
		    }
}" 2> /dev/null
}


enable_ntp () { 
	#Set the use ntp option to true
	pdsh -f 24 -R exec -w $range curl --netrc-file $NETRCFILE -H "Content-Type: application/json" -X PATCH https://%h${ILO_DOMAIN}/redfish/v1/Managers/1/EthernetInterfaces/1/ --insecure  -s -w '\n' -m 5 -d \
'{
	"DHCPv4": {
	        "UseNTPServers": true
		  }
}' 2> /dev/null

	echo ""
	echo "You must reboot the iLOs for this change to take effect."
	echo ""
	echo "Use 'cm-ilo reboot-ilo' to reboot iLOs"
	echo ""

}

check_ntp () {

	echo "Checking iLO NTP server address" 
	echo ""

	pdsh_out=$(pdsh -R exec -w $range curl --netrc-file $NETRCFILE https://%h${ILO_DOMAIN}/redfish/v1/Managers/1/DateTime/ -s --insecure  -s -w '\n' -m 5 --insecure 2> $OFFLINE_NODES)

	#split the pdsh hostname so jq can be used on the json variable.
	while read -r i j;
	do 
		ilo_ntp_ip=$(echo "$j" | jq .NTPServers 2> /dev/null | grep -oE '((1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])\.){3}(1?[0-9][0-9]?|2[0-4][0-9]|25[0-5])' | sed '/^[[:space:]]*$/d')
		if [ -z "$ilo_ntp_ip" ]
		then
		ilo_ntp_ip="Nil IP found"
		fi
		printf "$i "; echo $ilo_ntp_ip
	done <<< "$pdsh_out" |sort -k1 |dshbak -c
	echo ""

	echo "Checking iLO Timezone" 
	echo ""
	pdsh_out=$(pdsh -R exec -w $range curl --netrc-file $NETRCFILE https://%h${ILO_DOMAIN}/redfish/v1/Managers/1/DateTime/ -s --insecure  -s -w '\n' -m 5 --insecure 2> $OFFLINE_NODES)

	#split the pdsh hostname so jq can be used on the json variable.
	while read -r i j;
	do 
		ilo_tz=$(echo "$j" | jq '.TimeZone.Index' 2> /dev/null)
		if [ -z "$ilo_tz" ]
		then
			ilo_tz="Nil timezone found"
		fi
		printf "$i "; echo $ilo_tz
	done <<< "$pdsh_out" |sort -k1 |dshbak -c
	echo ""
	exit 0
}

#if check not specified on command line then make changes
if [ "$2" != "check" ]
then
	disable_ntp
	set_tz
	enable_ntp
fi

#carry out check only if specified on command line
check_ntp
