# This script will rollback the new VPN(s) and VGW
# INPUT - Permission to delete the new VPN(s) and new VGW
# OUTPUT - Deleted new VPN(s) and VGW
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

# Get the AWS Region and new VGW Id from the stored data
region=`cat $migData | grep "AWS Region:" | tail -n 1 | tr -s " " | cut -d":" -f2`
newVgw=`cat $migData | grep "New VGW:" | tail -n 1 | cut -d":" -f2 | sed 's/ //g'`

declare -a newVpn
declare -a delVpn

# Get the list of new VPNs created
oldVpn=(`cat $migData | grep "VPN Connections:" | tail -n 1 | cut -d":" -f2`)
numOldVpn=${#oldVpn[@]}
newVpn=(`cat $migData | grep Classic | tail -n $numOldVpn | awk '{print $NF}'`)
echo ""
echo "Do you want to delete new VPNs or new VGW? Please enter 'vpn' or 'vgw'"
read option

# Delete the New VPNs
# Go through each New VPN, if its already deleted, skip it and move to the next one
while true; do
 if [ "$option" == "vpn" ]; then
  echo ""
  for vpnState in ${newVpn[@]}; do
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

# If all New VPNs have been deleted already, log and exit
  if [ ${#delVpn[@]} == 0 ]; then
   echo "All new VPNs have been deleted already"
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
    numVpn=${#delVpn[@]}
    counter=0
    echo "Deleting new VPN" >> $migData
    echo "" >> $migData
    while [ $counter -lt $numVpn ]; do
     echo ""
     echo "Deleting the VPN ${delVpn[$counter]}"
     echo "" >> $migData
     echo `date` >> $migData
     `aws ec2 delete-vpn-connection --vpn-connection-id ${delVpn[$counter]} --region $region`
     echo "Deleted VPN ${delVpn[$counter]}" >> $migData
     echo "Deleted VPN ${delVpn[$counter]}"
     counter=$[$counter + 1]
    done
	echo "################################################################################" >> $migData
	echo ""

# Once VPNs are deleted, give option to also delete VGW
# If yes - Proceed to deleting of VGW
# If no - Abort and exit
# Anything else - Ask to re-enter the option
    echo ""
    echo "Do you also want to delete the new VGW $newVgw? Please enter 'yes' or 'no'"
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
    echo "Aborting - Not deleting new VPNs"
    exit 1
   else
    echo ""
	echo "Please enter a valid option: 'yes' or 'no'"
	read opt
   fi
  done

# Delete the new VGW
# If the new VGW is already deleted, log and exit
# Checks before deleting VGW:
# isVpnOnVgw1 - Are there any VPNs on the VGW
# isVpnOnVgw2 - Are the VPNs on the VGW in available state. If not, it means they are deleted
# isVpnOnVgw3 - Is the VGW attached to the VPC
 elif [ "$option" == "vgw" ]; then
  echo ""
  `aws ec2 describe-vpn-gateways --vpn-gateway-ids $newVgw --region $region &> temp$newVgw.txt`
  stat=`echo $?`
  if [ $stat != 255 ]; then
   isVgwAvail=`cat temp$newVgw.txt | grep "available" | wc -l`
   rm -f temp$newVgw.txt
   if [ $isVgwAvail == 1 ]; then
    isVpnOnVgw1=`aws ec2 describe-vpn-connections --filters Name=vpn-gateway-id,Values=$newVgw --region $region | grep "VpnConnectionId" | wc -l`
    isVpnOnVgw2=`aws ec2 describe-vpn-connections --filters Name=vpn-gateway-id,Values=$newVgw --region $region | grep "State" | sed -ne '/,/p' | grep "available" | wc -l`
	isVpnOnVgw3=`aws ec2 describe-vpn-gateways --vpn-gateway-id $newVgw --region $region | grep "attached" | wc -l`
	if [ $isVpnOnVgw1 -gt 0 ]; then
	 if [ $isVpnOnVgw2 -gt 0 ]; then
	  echo "The new VGW $newVgw has VPNs associated with it. Please delete the VPNs before deleting this VGW"
	  echo "Exiting the script"
	  exit 1
	 elif [ $isVpnOnVgw3 == 1 ]; then
	  echo "The new VGW $newVgw is attached to a VPC. Please detach the VGW before deleting the VGW"
	  echo "Exiting the script"
	  exit 1
	 else 
      echo "The following VGW will be deleted"
      echo $newVgw
	 fi
	else
	 echo "The following VGW will be deleted"
     echo $newVgw
	fi
   else
    echo "New VGW $newVgw is already deleted"
    echo "Exiting the script"
    exit 1
   fi
  else
   echo "New VGW $newVgw is already deleted"
   echo "Exiting the script"
   exit 1
  fi
  echo ""
  echo "Do you want to continue? Please enter 'yes' or 'no'"
  read opt
  while true; do
   if [ "$opt" == "yes" ]; then
    echo ""
    echo "Deleting new VGW $newVgw"
    echo "Deleting new VGW" >> $migData
    echo "" >> $migData
    echo `date` >> $migData
    `aws ec2 delete-vpn-gateway --vpn-gateway-id $newVgw --region $region`
    echo "Deleted VGW: $newVgw" >> $migData
    echo "Deleted VGW $newVgw"
    echo "################################################################################" >> $migData
    exit 1
   elif [ "$opt" == "no" ]; then
    echo ""
    echo "Aborting - Not deleting new VGW"
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
