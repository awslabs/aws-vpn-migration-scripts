# This script will be used to clean all the Classic resources - VPN(s) and VGW
# INPUT - Permission to delete old VPN(s) and VGW
# OUTPUT - Deleted old VPN(s) and VGW
# ERROR CHECKS - NONE

#! /bin/bash

res="resources.txt"

# This function handles a Keyboard Interrupt
# It will be logged and stored
kbInrpt ()
{
 echo ""
 echo "Keyboard Interrupt detected"
 echo "Exiting the script"
 exit 1
}

trap kbInrpt SIGINT

# Depending on the old VGW, select the migration data file
# If there is only 1 VGW in resources.txt, use the migration data file
# If there are multiple VGWs in resources.txt, ask to enter the VGW to proceed, and then select the migration data file
# Resources.txt - File to store the old VGWs
numOldVgw=`cat $res | cut -d":" -f2 | wc -l`
if [ $numOldVgw -eq 1 ]; then
 vgw=`cat $res |  cut -d":" -f2 | sed 's/ //g'`
 migData="migration_$vgw.txt"
else
 oldVgwList=(`cat $res | cut -d":" -f2`)
 echo ""
 echo "Please re-enter the VGW for which you would like to proceed with migration"
 echo "Here is the list of VGWs:"
 echo ${oldVgwList[@]}
 read vgw
 
# Make sure that the correct VGW Id is entered
# If correct - Reference the proper migration file
# If incorrect - Ask for valid VGW Id
 vgwCorrect=0
 while true; do
  for vgate in ${oldVgwList[@]}; do
   if [ "$vgate" == "$vgw" ]; then
    vgwCorrect=1
   fi
  done
  if [ $vgwCorrect == 0 ]; then
   echo ""
   echo "Please enter a valid VGW from the list - ${oldVgwList[@]}"
   read vgw
  elif [ $vgwCorrect == 1 ]; then
   migData="migration_$vgw.txt"
   break
  fi
 done
fi

# Get the old VPNs (Classic), the old VGW, and the AWS Region
region=`cat $migData | grep "AWS Region:" | tail -n 1 | cut -d":" -f2`
oldVgw=`cat $migData | grep "Old VGW:" | tail -n 1 | cut -d":" -f2 | sed 's/ //g'`
oldVpn=(`cat $migData | grep "VPN Connections:" | tail -n 1 | cut -d":" -f2`)
numOldVpn=${#oldVpn[@]}
declare -a delVpn
 
echo ""
echo "Do you want to delete Classic VPNs or old VGW? Please enter 'vpn' or 'vgw'"
read option

# Delete the Classic VPNs
# Go through each Classic VPN, if its already deleted, skip it and move to the next one
while true; do
 if [ "$option" == "vpn" ]; then
  echo ""
  for vpnState in ${oldVpn[@]}; do
   `aws ec2 describe-vpn-connections --vpn-connection-ids $vpnState --region $region &> temp$vpnState.txt`
   stat=`echo $?`
   if [ $stat != 255 ]; then
    isVpnAvail=`cat temp$vpnState.txt | grep "available" | tail -n 1 | wc -l`
    rm -f temp$vpnState.txt
    if [ $isVpnAvail == 1 ]; then
     echo "VPN to be deleted: $vpnState"
	 delVpn+=($vpnState)
    fi
   fi
  done
 
# If all Classic VPNs have been deleted already, log and exit
  if [ ${#delVpn[@]} == 0 ]; then
   echo "All Classic VPNs have been deleted already"
   echo "Exiting the script"
   exit 1
  fi
  echo ""
  echo "Do you want to continue? Please enter 'yes' or 'no'"
  read opt
  
# Make sure that only yes or no are entered
# If yes - Delete the VPNs
# If no - Abort and exit
# Anything else - Ask to re-enter the option
  while true; do
   if [ "$opt" == "yes" ]; then
    counter=0
	echo "Deleting old VPN" >> $migData
    echo "" >> $migData
    while [ $counter -lt $numOldVpn ]; do
     echo ""
     echo "Deleting the VPN ${oldVpn[$counter]}"
     echo "" >> $migData
     echo `date` >> $migData
     `aws ec2 delete-vpn-connection --vpn-connection-id ${oldVpn[$counter]} --region $region`
     echo "Deleted VPN ${oldVpn[$counter]}" >> $migData
     echo "Deleted VPN ${oldVpn[$counter]}"
     counter=$[$counter + 1]
    done
	echo "################################################################################" >> $migData
	echo "" >> $migData

# Once VPNs are deleted, give option to also delete VGW
# If yes - Proceed to deleting of VGW
# If no - Abort and exit
# Anything else - Ask to re-enter the option
    echo ""
    echo "Do you also want to delete the old VGW $oldVgw? Please enter 'yes' or 'no'"
	read vgwOpt
	while true; do
	 if [ "$vgwOpt" == "yes" ]; then
	  option="vgw"
	  break
	 elif [ "$vgwOpt" == "no" ]; then
	  echo "Exiting the script"
	  exit 1
	 else
	  echo ""
	  echo "Please enter a valid option: 'yes' or 'no'"
	  read vgwOpt
	 fi
	done
	break
   elif [ "$opt" == "no" ]; then
    echo ""
    echo "Aborting - Not deleting Classic VPNs"
    exit 1
   else
    echo ""
	echo "Please enter a valid option: 'yes' or 'no'"
	read opt
   fi
  done

# Delete the old VGW
# If the old VGW is already deleted, log and exit
# Checks before deleting VGW:
# isVpnOnVgw1 - Are there any VPNs on the VGW
# isVpnOnVgw2 - Are the VPNs on the VGW in available state. If not, it means they are deleted
# isVpnOnVgw3 - Is the VGW attached to the VPC
 elif [ "$option" == "vgw" ]; then
  echo ""
  `aws ec2 describe-vpn-gateways --vpn-gateway-ids $oldVgw --region $region &> temp$oldVgw.txt`
  stat=`echo $?`
  if [ $stat != 255 ]; then
   isVgwAvail=`cat temp$oldVgw.txt | grep "available" | wc -l`
   rm -f temp$oldVgw.txt
   if [ $isVgwAvail == 1 ]; then
    isVpnOnVgw1=`aws ec2 describe-vpn-connections --filters Name=vpn-gateway-id,Values=$oldVgw --region $region | grep "VpnConnectionId" | wc -l`
	isVpnOnVgw2=`aws ec2 describe-vpn-connections --filters Name=vpn-gateway-id,Values=$oldVgw --region $region | grep "State" | sed -ne '/,/p' | grep "available" | wc -l`
	isVpnOnVgw3=`aws ec2 describe-vpn-gateways --vpn-gateway-id $oldVgw --region $region | grep "attached" | wc -l`
	if [ $isVpnOnVgw1 -gt 0 ]; then
	 if [ $isVpnOnVgw2 -gt 0 ]; then
	  echo "The old VGW $oldVgw has VPNs associated with it. Please delete the VPNs before deleting this VGW"
	  echo "Exiting the script"
	  exit 1
	 elif [ $isVpnOnVgw3 == 1 ]; then
	  echo "The new VGW $oldVgw is attached to a VPC. Please detach the VGW before deleting the VGW"
	  echo "Exiting the script"
	  exit 1
	 else
      echo "The following VGW will be deleted"
      echo $oldVgw
	 fi
	else
	 echo "The following VGW will be deleted"
     echo $oldVgw
	fi
   else
    echo "Old VGW $oldVgw is already deleted"
	echo "Exiting the script"
	exit 1
   fi
  else
   echo "Old VGW $oldVgw is already deleted"
   echo "Exiting the script"
   exit 1
  fi
  echo ""
  echo "Do you want to continue? Please enter 'yes' or 'no'"
  read opt
  while true; do
   if [ "$opt" == "yes" ]; then
    echo ""
    echo "Deleting old VGW $oldVgw"
    echo "Deleting old VGW" >> $migData
    echo "" >> $migData
    echo `date` >> $migData
    `aws ec2 delete-vpn-gateway --vpn-gateway-id $oldVgw --region $region`
    echo "Deleted Old VGW: $oldVgw" >> $migData
    echo "Deleted Old VGW $oldVgw"
    echo "################################################################################" >> $migData
    exit 1
   elif [ "$opt" == "no" ]; then
    echo ""
    echo "Aborting - old VGW $oldVgw not deleted"
    exit 1
   else
    echo ""
	echo "Please enter a valid option: 'yes' or 'no'"
	read opt
   fi
  done
 else
  echo ""
  echo "Please enter a valid option: 'vpn' or 'vgw'"
  read option
 fi
done
