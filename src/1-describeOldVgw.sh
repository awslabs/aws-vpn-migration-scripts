# This script will be used to store important information regarding the VGW, that will be used in the process of migration.
# INPUTS - VGW Id of the old VGW, AWS Region
# OUTPUTS - VPN Information (Routing Type - BGP/Static, CGW Id), Static Routes (for static VPNs)
# ERROR CHECKS - 
# AWS Region should be correct, VGW should exist in that region, VGW should have all Classic VPNs
# VGW should have atleast 1 Classic VPN, VGW should not have any DX resources

#! /bin/bash

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

# This function will check if the VGW exists in the given region
vgwExists ()
{
 `aws ec2 describe-vpn-gateways --vpn-gateway-id $oldVgw --region $region &> /dev/null`
 vgwNotExists=`echo $?`
 while [ $vgwNotExists == 255 ]; do
  echo ""
  echo "The VGW $oldVgw does not exist. Please enter a valid VGW associated with Classic VPN(s) in $region:"
  read oldVgw
  `aws ec2 describe-vpn-gateways --vpn-gateway-id $oldVgw --region $region &> /dev/null`
  vgwNotExists=`echo $?`
 done
 oldVgw=$oldVgw
}

# This function does the following checks
# 1 - If VGW does not have any VPNs on it, exit the script
# 2 - If VGW has atleast 1 AWS VPN on it, get a valid VGW
vgwVpnCheck ()
{
 vgwAws=`aws ec2 describe-vpn-connections --region $region --filters Name=vpn-gateway-id,Values=$oldVgw | grep '"Category": "VPN"' | wc -l`
 vgwClassic=`aws ec2 describe-vpn-connections --region $region --filters Name=vpn-gateway-id,Values=$oldVgw | grep '"Category": "VPN-Classic"' | wc -l`
 if (( $vgwAws == 0 && $vgwClassic == 0 )); then
  echo ""
  echo "There are no VPNs associated with the VGW $oldVgw"
  echo "Exiting the script"
  exit 1
 else
  while [ $vgwAws -ne 0 ]; do
  echo ""
  echo "The VGW $oldVgw has atleast 1 AWS VPN associated with it. Please enter a VGW associated with Classic VPN(s) in $region:"
   read oldVgw
   vgwExists $oldVgw
   vgwAws=`aws ec2 describe-vpn-connections --region $region --filters Name=vpn-gateway-id,Values=$oldVgw | grep '"Category": "VPN"' | wc -l`
   vgwClassic=`aws ec2 describe-vpn-connections --region $region --filters Name=vpn-gateway-id,Values=$oldVgw | grep '"Category": "VPN-Classic"' | wc -l`
   if (( $vgwAws == 0 && $vgwClassic == 0 )); then
    echo ""
    echo "There are no VPNs associated with the VGW $oldVgw"
    echo "Exiting the script"
    exit 1
   fi
  done
 fi
 oldVgw=$oldVgw
}


# Resources.txt - Store the old VGW List
res="resources.txt"
`touch resources.txt`

# Declare variables used to store data regarding the old VGWs
declare -a vpnList
declare -a cgwList
declare -a routingTypeList
declare -a route
declare -a staticRoute

# List of AWS Regions with Classic VPNs
regionList=(us-east-1 us-west-1 us-west-2 eu-west-1 eu-central-1 ap-southeast-1 ap-southeast-2 ap-northeast-1 sa-east-1)

echo "Please enter the AWS Region in which you have Classic VPN(s) [Format - us-east-1]:"
read region
regFlag=0

# Region should exist in the list of regions with Classic VPNs
while [ $regFlag == 0 ]; do
 for reg in "${regionList[@]}"; do
  if [ "$reg" == "$region" ]; then
   regFlag=0
   break
  else
   regFlag=1
  fi
 done
 if [ $regFlag == 1 ]; then
  echo ""
  echo "Please enter the AWS Region in which you have Classic VPN(s) [Format - us-east-1]:"
  read region
  regFlag=0
 else
  break
 fi
done

# Get the old VGW
echo ""
echo "Please enter the VGW associated with Classic VPN(s) in $region:"
read oldVgw

# Check 1 - VGW exists in the region
vgwExists $oldVgw

# Check 2 - VGW does not have an AWS VPN
# If there is atleast 1 AWS VPN on the VGW, re-enter the VGW with only Classic VPNs on it
vgwVpnCheck $oldVgw

# Check if there are any DX resources on the VGW
# DX Resources - VIFs on VGW OR VGW associated with DXGW
# If yes, give a warning about not proceeding
# If no, proceed
isDxVif=`aws directconnect describe-virtual-interfaces --region $region | grep $oldVgw`
isDxGw=`aws directconnect describe-direct-connect-gateway-associations --virtual-gateway-id $oldVgw --region $region | grep $oldVgw`
if [ $isDxVif ]; then
 echo ""
 echo "Your VGW is affiliated with Direct Connect resources. We do not recommend using these scripts to migrate VGWs with Direct Connect objects"
 echo "Exiting the script"
 exit 1
elif [ $isDxGw ]; then
 echo ""
 echo "Your VGW is affiliated with Direct Connect resources. We do not recommend using these scripts to migrate VGWs with Direct Connect objects."
 echo "Exiting the script"
 exit 1
else

# If the Old VGW is already stored in resources.txt, give an option of not storing the details again
 isOldVgwInRes=`cat $res | grep $oldVgw | wc -l`
 if [ $isOldVgwInRes -eq 0 ]; then
  echo "Old VGW: $oldVgw" >> $res
 else
  echo ""
  echo "You have already stored the information for this VGW"
  echo "Do you still want to proceed? Please enter 'yes' or 'no'"
  read procOpt
  
# Make sure that only yes or no are entered as the options
# If no - Exit
# If yes - Proceed
# Other options - Ask to enter option again
  while true; do
   if [ $procOpt == "no" ]; then
    echo ""
    echo "Exiting the script"
    exit 1
   elif [ $procOpt == "yes" ]; then
    break
   else
    echo "Please enter a valid option: 'yes' or 'no'"
    read procOpt
   fi
  done
 fi 
 
 # Store the Old VGW information
 migData="migration_$oldVgw.txt"
 echo ""
 echo "Storing information in $migData"
 echo "Storing Information on Old VGW" >> $migData
 echo "" >> $migData
 echo `date` >> $migData
 echo "Old VGW: $oldVgw" >> $migData
 echo "AWS Region: $region" >> $migData
 echo "" >> $migData
 
 # Store the VPNs and CGWs in the respective array
 vpnCount=`aws ec2 describe-vpn-connections --region $region --filters Name=vpn-gateway-id,Values=$oldVgw | grep VpnConnectionId | wc -l`
 counter=1
 while [ $counter -le $vpnCount ]; do
  vpn=`aws ec2 describe-vpn-connections --region $region --filters Name=vpn-gateway-id,Values=$oldVgw | grep VpnConnectionId | awk "NR == ${counter}" | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
  cgw=`aws ec2 describe-vpn-connections --region $region --vpn-connection-id ${vpn} | grep CustomerGatewayId | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
  vpnList+=($vpn)
  cgwList+=($cgw)
  
# For static VPNs, store the static routes in the array
# Also store the routing type as Static for static VPNs
# For BGP VPNs, store the routing type as BGP
  isStatic=`aws ec2 describe-vpn-connections --region $region --vpn-connection-id ${vpn} | grep StaticRoutesOnly | cut -d":" -f2`
  if [ ${isStatic} == "true" ]; then
    routingType="Static"
    routeCount=`aws ec2 describe-vpn-connections --region $region --vpn-connection-id ${vpn} | grep DestinationCidrBlock | wc -l`
    rcounter=0
    nrc=1
    while [ $rcounter -lt $routeCount ]; do
     route[${rcounter}]=`aws ec2 describe-vpn-connections --region $region --vpn-connection-id ${vpn} | grep DestinationCidrBlock | awk "NR == ${nrc}" | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
     rcounter=$[$rcounter + 1]
     nrc=$[$nrc + 1]
    done
    staticRoute+=("Routes for$vpn: $(echo "${route[*]}")")
    routingTypeList+=($routingType)
  else
    routingType="BGP"
    routingTypeList+=($routingType)
  fi
  counter=$[$counter + 1]
 done 

# Log all information into the file
# Information - VPNs, CGWs, Routing Types, Static Routes, Amazon-Side BGP ASN
 echo "VPN Connections: ${vpnList[@]}" >> $migData
 echo "CGW Ids: ${cgwList[@]}" >> $migData
 echo "Routing Types: ${routingTypeList[@]}" >> $migData
 echo "" >> $migData
 printf '%s\n' "${staticRoute[@]}" >> $migData
fi

echo "################################################################################" >> $migData
echo "" >> $migData
echo ""
echo "Please check $migData for the information regarding $oldVgw"
