# This script will be used to create AWS VPNs on the new VGW
# This script will create 1 AWS VPN for each Classic VPN
# INPUT - Option to select how the VPN will be created (manual/auto-generated tunnel IPs/PSKs, original configuration)
# OUTPUT - 1 AWS VPN per Classic VPN
# ERROR CHECKS - 
# Sanity Check for Inside Tunnel IP CIDRs and PSKs

#! /bin/bash

res="resources.txt"
declare -a vpn
declare -a cgw
declare -a routingType
declare -a routes
declare -a usedTunnel

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

# Get the AWS Region and the new VGW Id from the stored data
newVgw=`cat $migData | grep "New VGW:" | tail -n 1 | cut -d":" -f2 | sed 's/ //g'`
region=`cat $migData | grep "AWS Region:" | tail -n 1 | cut -d":" -f2`

# Get the VPN, CGW, and Routing Type data from the stored information
vpn=(`cat $migData | grep "VPN Connections:" | tail -n 1 | cut -d":" -f2`)
cgw=(`cat $migData | grep "CGW Ids:" | tail -n 1 | cut -d":" -f2`)
routingType=(`cat $migData | grep "Routing Types:" | tail -n 1 | cut -d":" -f2`)

# This function will validate Tunnel Inside IP CIDR
# Checks done:
# 1. CIDR should be in the allowed range
# 2. CIDR should have the correct format - 169.254.x.x/30
# 3. CIDR should not be associated with another VPN on the same VGW
checkInsideIpCidr () {
 local tunnelIp=$1
 local tunnel=$2
 formFlag=0

# Convert the CIDR to the form 169.254.x.y/30, where y is 0 or multiple of 4
 while [ $formFlag == 0 ]; do
  octThree=$(echo $tunnelIp | cut -d. -f3)
  octFour=$(echo $tunnelIp | cut -d. -f4 | cut -d/ -f1)
  octFourMod=$[$octFour % 4]
  if [ $octFourMod -gt 0 ]; then
   octFourUpdated=$[$octFour - $octFourMod]
   tunIpStaticFone=169.254.$octThree.$octFourUpdated/30
  else
   tunIpStaticFone=169.254.$octThree.$octFour/30 
  fi
 
# This CIDR should not be already used for another VPN on the same VGW
  cidrFlag=0
  while [ $cidrFlag == 0 ]; do
   if [ ${#usedTunnel[@]} -gt 0 ]; then
    for used in "${usedTunnel[@]}"; do
     if [ "$used" == "$tunIpStaticFone" ]; then
      echo ""
      echo "This Inside Tunnel IP CIDR is used once for a VPN associated with this VGW. Please enter a different CIDR"
      read tunnelIp
	  octThree=$(echo $tunnelIp | cut -d. -f3)
      octFour=$(echo $tunnelIp | cut -d. -f4 | cut -d/ -f1)
	  octFourMod=$[$octFour % 4]
      if [ $octFourMod -gt 0 ]; then
       octFourUpdated=$[$octFour - $octFourMod]
       tunIpStaticFone=169.254.$octThree.$octFourUpdated/30
      else
	   tunIpStaticFone=169.254.$octThree.$octFour/30
	  fi
	  cidrFlag=0
	  break
	 else
	  cidrFlag=1
	 fi
    done
   else
    cidrFlag=1 
   fi
  done

# Check the format of the CIDR. It should be - 169.254.x.x/30
  if [ $(echo $tunnelIp | grep -E "169.254.[0-9]{1,3}\.[0-9]{1,3}\/30" | wc -l) -ne 1 ]; then
   echo ""
   echo "Please enter the Inside Tunnel IP CIDR in the valid format - 169.254.x.x/30"
   read tunnelIp
  else

# If format is correct, make sure that the CIDR is in the allowed range, and is a valid IP address
# Valid IP Address - 3rd and 4th Octet should not be greater than 255
   if [[ $octThree -eq 0 || $octThree -eq 1 || $octThree -eq 2 || $octThree -eq 3 || $octThree -eq 4 || $octThree -eq 5 ]]; then
    if [[ $octFour -eq 0 || $octFour -eq 1 || $octFour -eq 2 || $octFour -eq 3 ]]; then
     echo ""
     echo "Please enter the allowed Inside Tunnel IP CIDR only"
     read tunnelIp
    elif [ $(echo $tunnelIp | cut -d. -f4 | cut -d/ -f1) -gt 255 ]; then
     echo ""
     echo "Please enter a valid IP CIDR"
     read tunnelIp
    else
     formFlag=1
     octFourMod=$[$octFour % 4]
     if [ $octFourMod -gt 0 ]; then
      octFour=$[$octFour - $octFourMod]
      tunnelIp=169.254.$octThree.$octFour/30
     fi
    fi 
   elif [ $octThree -eq 169 ]; then
    if [[ $octFour -eq 252 || $octFour -eq 253 || $octFour -eq 254 || $octFour -eq 255 ]]; then 
     echo ""   
     echo "Please enter the allowed Inside Tunnel IP CIDR only"
     read tunnelIp
    elif [ $(echo $tunnelIp | cut -d. -f4 | cut -d/ -f1) -gt 255 ]; then
     echo ""
     echo "Please enter a valid IP CIDR"
     read tunnelIp
    else
     formFlag=1
     octFourMod=$[$octFour % 4]
     if [ $octFourMod -gt 0 ]; then
      octFour=$[$octFour - $octFourMod]
      tunnelIp=169.254.$octThree.$octFour/30
     fi
    fi
   elif [ $(echo $tunnelIp | cut -d. -f3) -gt 255 ]; then
    echo ""
    echo "Please enter a valid IP CIDR"
    read tunnelIp
   elif [ $(echo $tunnelIp | cut -d. -f4 | cut -d/ -f1) -gt 255 ]; then
    echo ""
    echo "Please enter a valid IP CIDR"
    read tunnelIp
   else
    formFlag=1
    octFourMod=$[$octFour % 4]
    if [ $octFourMod -gt 0 ]; then
     octFour=$[$octFour - $octFourMod]
     tunnelIp=169.254.$octThree.$octFour/30
    fi
   fi
  fi
 done
 
# Add the CIDR to the usedTunnel array to ensure it will not be used again
# If 2nd argument to this function is tunnel1 - The CIDR will be used for first tunnel
# If 2nd argument to this function is tunnel2 - The CIDR will be used for second tunnel
 usedTunnel+=("$tunnelIp")
 if [ $tunnel == "tunnel1" ]; then
  tunnelF=$tunnelIp
 elif [ $tunnel == "tunnel2" ]; then
  tunnelS=$tunnelIp
 fi
}

# This function will validate the preshared key
# Checks done:
# 1. Preshared key can be 8 to 64 characters long
# 2. Preshared key cannot start with 0
# 3. Preshared key can contain alphabets, numbers, underscore, and period
checkPsk () {
 psk=$1
 tunnel=$2
 isPrefCorrect=`echo $psk | grep -E "^[a-zA-Z1-9_.][a-zA-Z0-9_.]{7,63}$" | wc -l`
 while [ $isPrefCorrect == 0 ]; do
  echo ""
  echo "Please enter a valid Preshared Key:"
  read psk
  isPrefCorrect=`echo $psk | grep -E "^[a-zA-Z1-9_.][a-zA-Z0-9_.]{7,63}$" | wc -l`
 done
 
# If 2nd argument to this function is tunnel1 - The PSK will be used for first tunnel
# If 2nd argument to this function is tunnel2 - The PSK will be used for second tunnel
 if [ $tunnel == "tunnel1" ]; then
  preF=$psk
 elif [ $tunnel == "tunnel2" ]; then
  preS=$psk
 fi  
}

# This function will determine the Inside Tunnel IP CIDR
# This will be executed only when option 0 or option 1 is selected to create a VPN
getInsideIpCidr () {
 vpnId=$1
 cidrList=(`aws ec2 describe-vpn-connections --vpn-connection-ids $vpnId --region $region | grep CustomerGatewayConfiguration | grep -oE "169\.254\.[0-9]{1,3}\.[0-9]{1,3}" | awk "NR % 2 == 1"`)
 for i in `seq 0 1`; do
  octFour=$(echo ${cidrList[$i]} | cut -d. -f4)
  octThree=$(echo ${cidrList[$i]} | cut -d. -f3)
  octFour=$[$octFour - 2]
  cidrList[$i]=169.254.$octThree.$octFour/30
  
# Once we have the inside IP CIDR, make sure they pass the checks 
  checkInsideIpCidr ${cidrList[$i]} tunnel$((i+1))
 done
 
# Store the returned valid CIDRs for the first and second tunnels
 insideIpCidrList=("$tunnelF")
 insideIpCidrList+=("$tunnelS")
}

# For each VPN, customers can choose 1 out of the 4 options
# 0 - Creating VPN with same Inside Tunnel IP CIDRs and Preshared Keys as the Original VPN
# 1 - Creating VPN with auto-generated Inside Tunnel IP CIDRs and Preshared Keys
# 2 - Creating VPN with manually entered Inside Tunnel IP CIDRs and Preshared Keys
# 3 - Creating VPN with manually entered Inside Tunnel IP CIDRs and auto-generated Preshared Keys
# 4 - Creating VPN with auto-generated Inside Tunnel IP CIDRs and manually entered Preshared Keys

echo ""
echo "This script will create an AWS VPN for each corressponding Classic VPN"
echo "For each VPN, you will have the following options"
echo "0 - Creating VPN with same Inside Tunnel IP CIDRs and Preshared Keys as the Original VPN"
echo "1 - Creating VPN with auto-generated Inside Tunnel IP CIDRs and Preshared Keys"
echo "2 - Creating VPN with manually entered Inside Tunnel IP CIDRs and Preshared Keys"
echo "3 - Creating VPN with manually entered Inside Tunnel IP CIDRs and auto-generated Preshared Keys"
echo "4 - Creating VPN with auto-generated Inside Tunnel IP CIDRs and manually entered Preshared Keys"
echo ""
echo ""
echo "Rules for Inside Tunnel IP CIDRs:"
echo "You have to enter the CIDR in the range 169.254.0.0/16, with the format - 169.254.x.x/30"
echo "Following ranges are not allowed:"
echo "169.254.0.0/30, 169.254.1.0/30, 169.254.2.0/30, 169.254.3.0/30, 169.254.4.0/30, 169.254.5.0/30, 169.254.169.252/30"
echo "Please do not use the same CIDR for more than 1 VPN on the same VGW"
echo ""
echo ""
echo "Rules for Preshared Keys:"
echo "Preshared Keys can be 8 to 64 characters long"
echo "Allowed characters - Alphanumeric (alphabets and numbers), underscore(_), period (.)"
echo "Preshared Keys cannot start with 0"
echo ""

# For Static VPNs, also add the static routes to the VPN tunnel
# Before adding static routes, wait for the tunnel state to be available
echo "Creating New VPNs" >> $migData
numVpn=${#vpn[@]}
counter=0

# If a new VPN is already created, skip to the next one
# If all new VPNs are already created, log it, and exit the script
while [ $counter -lt $numVpn ]; do 
 vpnState=(`aws ec2 describe-vpn-connections --filters Name=customer-gateway-id,Values=${cgw[$counter]} Name=vpn-gateway-id,Values=$newVgw --region $region | grep State | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g' | sed 's/ //g'`)
 vpnCreated=0
 for state in ${vpnState[@]}; do
  if [[ "$state" == "available" || "$state" == "pending" ]]; then
   echo ""
   echo "A VPN to replace ${vpn[$counter]} is already created. Moving on to the next VPN"
   counter=$[$counter + 1]
   vpnCreated=1
  else
   vpnCreated=0
  fi
 done
 if [ $vpnCreated == 1 ]; then
  echo ""
  echo "New VPNs are already created on the VGW $newVgw"
  echo "Exiting the script"
  exit 1
 fi
 
 echo ""
 echo "Creating VPN with CGW:${cgw[$counter]} and New VGW:$newVgw to replace Classic VPN:${vpn[$counter]}"
 echo "This is a ${routingType[$counter]} VPN"
 echo ""
 echo "Enter one of the following options:"
 echo "Press 0 if - You want to use same Inside Tunnel IP CIDRs and Preshared Keys as the Original VPN"
 echo "Press 1 if - You want to autogenerate Inside Tunnel IP CIDRs and Preshared Keys"
 echo "Press 2 if - You want to manually enter Inside Tunnel IP CIDRs and Preshared Keys"
 echo "Press 3 if - You want to manually enter Inside Tunnel IP CIDRs, but auto-generate Preshared Keys"
 echo "Press 4 if - You want to auto-generate Inside Tunnel IP CIDRs, but manually enter Preshared Keys"
 read option
 if [ "${routingType[$counter]}" == "Static" ]; then
  case $option in
   0)
# Get the Inside Tunnel IP CIDRs and Preshared Keys from the current configuration file for the VPN
# Create new VPN using the same values for Inside Tunnel IP CIDRs and Preshared Keys
    getInsideIpCidr ${vpn[$counter]}
	
    pskList=(`aws ec2 describe-vpn-connections --vpn-connection-ids ${vpn[$counter]} --region $region | grep CustomerGatewayConfiguration | grep -oE "[a-zA-Z0-9_.]{32}"`)
    echo ""
    echo "Creating new VPN on VGW $newVgw as a replacement to Classic VPN ${vpn[$counter]}"
    echo "" >> $migData
    echo `date` >> $migData
    
    newVpn=`aws ec2 create-vpn-connection --type ipsec.1 --customer-gateway-id ${cgw[$counter]} --vpn-gateway-id $newVgw --options "{\"StaticRoutesOnly\":true,\"TunnelOptions\":[{\"TunnelInsideCidr\":"\"${insideIpCidrList[0]}\"",\"PreSharedKey\":"\"${pskList[0]}\""},{\"TunnelInsideCidr\":"\"${insideIpCidrList[1]}\"",\"PreSharedKey\":"\"${pskList[1]}\""}]}" --region $region | grep "VpnConnectionId" | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
    
	echo "New VPN to replace Classic VPN:${vpn[$counter]} - $newVpn" >> $migData
    echo "" >> $migData
    echo "Waiting for the new VPN $newVpn to be available. This may take few minutes"
    
# Wait till the new VPN moves from pending state to available
	isPending=`aws ec2 describe-vpn-connections --vpn-connection-id $newVpn --region $region | grep "pending" | wc -l`
    while [ $isPending -gt 0 ]; do
     sleep 30
     isPending=`aws ec2 describe-vpn-connections --vpn-connection-id $newVpn --region $region | grep "pending" | wc -l`
    done
 
# Once the new VPN is available, get the static routes from the old VPN and add it to the new VPN
    routes=(`cat $migData | grep "Routes for ${vpn[$counter]}" | cut -d":" -f2`)
    numRoutes=${#routes[@]}
    rcounter=0
	echo ""
    echo "New VPN $newVpn is now available. Adding static routes to the VPN"
    while [ $rcounter -lt $numRoutes ]; do
     `aws ec2 create-vpn-connection-route --vpn-connection-id $newVpn --region $region --destination-cidr-block ${routes[$rcounter]}`
     rcounter=$[$rcounter + 1]
    done
    echo "Added static routes to the VPN $newVpn"
    echo ""
    ;;
   1)
# Create a static VPN with auto-generated Inside Tunnel IP CIDRs and auto-generated Preshared Keys
# Wait for the VPN to be available, and then add static routes to the VPN
# Static routes are pulled from the old VPN data
    echo ""
    echo "Creating new VPN on VGW $newVgw as a replacement to Classic VPN ${vpn[$counter]}"
    echo "" >> $migData
    echo `date` >> $migData
	
    newVpn=`aws ec2 create-vpn-connection --type ipsec.1 --customer-gateway-id ${cgw[$counter]} --vpn-gateway-id $newVgw --options "{\"StaticRoutesOnly\":true}" --region $region | grep "VpnConnectionId" | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'` 
    echo "New VPN to replace Classic VPN:${vpn[$counter]} - $newVpn" >> $migData
    echo "" >> $migData
    echo "Waiting for the new VPN $newVpn to be available. This may take few minutes"
    
# Wait till the new VPN moves from pending state to available
	isPending=`aws ec2 describe-vpn-connections --vpn-connection-id $newVpn --region $region | grep "pending" | wc -l`
    while [ $isPending -gt 0 ]; do
     sleep 30
     isPending=`aws ec2 describe-vpn-connections --vpn-connection-id $newVpn --region $region | grep "pending" | wc -l`
    done
 
# Once the new VPN is available, get the static routes from the old VPN and add it to the new VPN
    routes=(`cat $migData | grep "Routes for ${vpn[$counter]}" | cut -d":" -f2`)
    numRoutes=${#routes[@]}
    rcounter=0
    echo "New VPN $newVpn is now available. Adding static routes to the VPN"
    while [ $rcounter -lt $numRoutes ]; do
     `aws ec2 create-vpn-connection-route --vpn-connection-id $newVpn --region $region --destination-cidr-block ${routes[$rcounter]}`
     rcounter=$[$rcounter + 1]
    done
    echo "Added static routes to the VPN $newVpn"
    echo ""
	
# Get the Inside Tunnel IP CIDRs from the current configuration file for the new VPN
# Add the Inside Tunnel IP CIDRs to the usedTunnel array
	getInsideIpCidr $newVpn
    ;;
   2)
# Create a static VPN with manually entered Inside Tunnel IP CIDRs and manually generated Preshared Keys
# For Inside Tunnel IP CIDRs, run all the checks to ensure sanity of the CIDRs
# For Preshared Keys, run all the checks to ensure sanity of the keys

# Inside Tunnel IP CIDR for Tunnel 1
    echo ""
    echo "Enter the Inside Tunnel IP CIDR for tunnel 1:"
    read tunnelF
    
# Check 1 - Inside Tunnel IP CIDR is not being used on the same VGW
# Check 2 - Format is 169.254.x.x/30
# Check 3 - Not allowed CIDRs - 169.254.0.0/30, 169.254.1.0/30, 169.254.2.0/30, 169.254.3.0/30, 169.254.4.0/30, 169.254.5.0/30, 169.254.169.252/30
# Check 4 - Valid IP address (3rd and 4th octet is not more than 255)
# Argument 1 - CIDR entered
# Argument 2 - To specify for which tunnel is the CIDR entered
    checkInsideIpCidr $tunnelF tunnel1

# Preshared Key for Tunnel 1
    echo ""
    echo "Enter the Preshared Key for tunnel 1:"
    read preF

# Make sure that the Preshared Key is as per the required format
# Argument 1 - PSK entered
# Argument 2 - To specify for which tunnel is the PSK entered
    checkPsk $preF tunnel1
	
# Inside Tunnel IP CIDR for Tunnel 2
    echo ""
    echo "Enter the Inside Tunnel IP CIDR for tunnel 2:"
    read tunnelS
    
# Check 1 - Inside Tunnel IP CIDR is not being used on the same VGW
# Check 2 - Format is 169.254.x.x/30
# Check 3 - Not allowed CIDRs - 169.254.0.0/30, 169.254.1.0/30, 169.254.2.0/30, 169.254.3.0/30, 169.254.4.0/30, 169.254.5.0/30, 169.254.169.252/30
# Check 4 - Valid IP address (3rd and 4th octet is not more than 255)
# Argument 1 - CIDR entered
# Argument 2 - To specify for which tunnel is the CIDR entered
    checkInsideIpCidr $tunnelS tunnel2
    

# Preshared Key for Tunnel 2 
    echo ""
    echo "Enter the Preshared Key for tunnel 2:"
    read preS

# Make sure that the Preshared Key is as per the required format
# Argument 1 - PSK entered
# Argument 2 - To specify for which tunnel is the PSK entered
    checkPsk $preS tunnel2
    
    echo ""
    echo "Creating new VPN on VGW $newVgw as a replacement to Classic VPN ${vpn[$counter]}"
    echo "" >> $migData
    echo `date` >> $migData
	
    newVpn=`aws ec2 create-vpn-connection --type ipsec.1 --customer-gateway-id ${cgw[$counter]} --vpn-gateway-id $newVgw --options "{\"StaticRoutesOnly\":true,\"TunnelOptions\":[{\"TunnelInsideCidr\":"\"$tunnelF\"",\"PreSharedKey\":"\"$preF\""},{\"TunnelInsideCidr\":"\"$tunnelS\"",\"PreSharedKey\":"\"$preS\""}]}" --region $region | grep "VpnConnectionId" | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
    echo "New VPN to replace Classic VPN:${vpn[$counter]} - $newVpn" >> $migData
    echo "" >> $migData
    echo "Waiting for the new VPN $newVpn to be available. This may take few minutes"
    
# Wait till the new VPN moves from pending state to available
	isPending=`aws ec2 describe-vpn-connections --vpn-connection-id $newVpn --region $region | grep "pending" | wc -l`
    while [ $isPending -gt 0 ]; do
     sleep 30
     isPending=`aws ec2 describe-vpn-connections --vpn-connection-id $newVpn --region $region | grep "pending" | wc -l`
    done
 
# Once the new VPN is available, get the static routes from the old VPN and add it to the new VPN
    routes=(`cat $migData | grep "Routes for ${vpn[$counter]}" | cut -d":" -f2`)
    numRoutes=${#routes[@]}
    rcounter=0
    echo "New VPN $newVpn is now available. Adding static routes to the VPN"
    while [ $rcounter -lt $numRoutes ]; do
     `aws ec2 create-vpn-connection-route --vpn-connection-id $newVpn --region $region --destination-cidr-block ${routes[$rcounter]}`
     rcounter=$[$rcounter + 1]
    done
    echo "Added static routes to the VPN $newVpn"
    echo ""
    ;;
   3)
# Create a static VPN tunnel with manually entered Inside Tunnel IP CIDRs and auto-generated Preshared Keys
# For Inside Tunnel IP CIDRs, run all the checks to ensure sanity of the CIDRs

# Inside Tunnel IP CIDR for Tunnel 1    
    echo ""
    echo "Enter the Inside Tunnel IP CIDR for tunnel 1:"
    read tunnelF
    
# Check 1 - Inside Tunnel IP CIDR is not being used on the same VGW
# Check 2 - Format is 169.254.x.x/30
# Check 3 - Not allowed CIDRs - 169.254.0.0/30, 169.254.1.0/30, 169.254.2.0/30, 169.254.3.0/30, 169.254.4.0/30, 169.254.5.0/30, 169.254.169.252/30
# Check 4 - Valid IP address (3rd and 4th octet is not more than 255)
# Argument 1 - CIDR entered
# Argument 2 - To specify for which tunnel is the CIDR entered
    checkInsideIpCidr $tunnelF tunnel1
    
# Inside Tunnel IP CIDR for Tunnel 2
    echo ""
    echo "Enter the Inside Tunnel IP CIDR for tunnel 2:"
    read tunnelS
    
# Check 1 - Inside Tunnel IP CIDR is not being used on the same VGW
# Check 2 - Format is 169.254.x.x/30
# Check 3 - Not allowed CIDRs - 169.254.0.0/30, 169.254.1.0/30, 169.254.2.0/30, 169.254.3.0/30, 169.254.4.0/30, 169.254.5.0/30, 169.254.169.252/30
# Check 4 - Valid IP address (3rd and 4th octet is not more than 255)
# Argument 1 - CIDR entered
# Argument 2 - To specify for which tunnel is the CIDR entered
    checkInsideIpCidr $tunnelS tunnel2
    

    echo ""
    echo "Creating new VPN on VGW $newVgw as a replacement to Classic VPN ${vpn[$counter]}"
    echo "" >> $migData
    echo `date` >> $migData
	
    newVpn=`aws ec2 create-vpn-connection --type ipsec.1 --customer-gateway-id ${cgw[$counter]} --vpn-gateway-id $newVgw --options "{\"StaticRoutesOnly\":true,\"TunnelOptions\":[{\"TunnelInsideCidr\":"\"$tunnelF\""},{\"TunnelInsideCidr\":"\"$tunnelS\""}]}" --region $region | grep "VpnConnectionId" | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
    echo "New VPN to replace Classic VPN:${vpn[$counter]} - $newVpn" >> $migData
    echo "" >> $migData
    echo "Waiting for the new VPN $newVpn to be available. This may take few minutes"
    
# Wait till the new VPN moves from pending state to available
	isPending=`aws ec2 describe-vpn-connections --vpn-connection-id $newVpn --region $region | grep "pending" | wc -l`
    while [ $isPending -gt 0 ]; do
     sleep 30
     isPending=`aws ec2 describe-vpn-connections --vpn-connection-id $newVpn --region $region | grep "pending" | wc -l`
    done

# Once the new VPN is available, get the static routes from the old VPN and add it to the new VPN
    routes=(`cat $migData | grep "Routes for ${vpn[$counter]}" | cut -d":" -f2`)
    numRoutes=${#routes[@]}
    rcounter=0
    echo "New VPN $newVpn is now available. Adding static routes to the VPN"
    while [ $rcounter -lt $numRoutes ]; do
     `aws ec2 create-vpn-connection-route --vpn-connection-id $newVpn --region $region --destination-cidr-block ${routes[$rcounter]}`
     rcounter=$[$rcounter + 1]
    done
    echo "Added static routes to the VPN $newVpn"
    echo ""
    ;;
   4)
# Create static VPN with manually entered Preshared Keys and auto-generated Inside Tunnel IP CIDRs
# For Preshared Keys, run all the checks to ensure sanity of the keys

# Preshared Key for Tunnel 1
    echo ""
    echo "Enter the Preshared Key for tunnel 1:"
    read preF

# Make sure that the Preshared Key is as per the required format
# Argument 1 - PSK entered
# Argument 2 - To specify for which tunnel is the PSK entered
    checkPsk $preF tunnel1
	
# Preshared Key for Tunnel 2
    echo ""
    echo "Enter the Preshared Key for tunnel 2:"
    read preS

# Make sure that the Preshared Key is as per the required format
# Argument 1 - PSK entered
# Argument 2 - To specify for which tunnel is the PSK entered
    checkPsk $preS tunnel2

    echo ""
    echo "Creating new VPN on VGW $newVgw as a replacement to Classic VPN ${vpn[$counter]}"
    echo "" >> $migData
    echo `date` >> $migData
	
    newVpn=`aws ec2 create-vpn-connection --type ipsec.1 --customer-gateway-id ${cgw[$counter]} --vpn-gateway-id $newVgw --options "{\"StaticRoutesOnly\":true,\"TunnelOptions\":[{\"PreSharedKey\":"\"$preF\""},{\"PreSharedKey\":"\"$preS\""}]}" --region $region | grep "VpnConnectionId" | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
    echo "New VPN to replace Classic VPN:${vpn[$counter]} - $newVpn" >> $migData
    echo "" >> $migData
    echo "Waiting for the new VPN $newVpn to be available. This may take few minutes"
   
# Wait till the new VPN moves from pending state to available
	isPending=`aws ec2 describe-vpn-connections --vpn-connection-id $newVpn --region $region | grep "pending" | wc -l`
    while [ $isPending -gt 0 ]; do
     sleep 30
     isPending=`aws ec2 describe-vpn-connections --vpn-connection-id $newVpn --region $region | grep "pending" | wc -l`
    done
 
# Once the new VPN is available, get the static routes from the old VPN and add it to the new VPN
    routes=(`cat $migData | grep "Routes for ${vpn[$counter]}" | cut -d":" -f2`)
    numRoutes=${#routes[@]}
    rcounter=0
    echo "New VPN $newVpn is now available. Adding static routes to the VPN"
    while [ $rcounter -lt $numRoutes ]; do
     `aws ec2 create-vpn-connection-route --vpn-connection-id $newVpn --region $region --destination-cidr-block ${routes[$rcounter]}`
     rcounter=$[$rcounter + 1]
    done
    echo "Added static routes to the VPN $newVpn"
    echo ""
	
# Get the Inside Tunnel IP CIDRs from the current configuration file for the new VPN
# Add the Inside Tunnel IP CIDRs to the usedTunnel array
	getInsideIpCidr $newVpn
    ;;
   *)
    echo ""
    echo "Please enter a valid option"
    continue
    ;;
  esac
 else
  case $option in
   0)
# Get the Inside Tunnel IP CIDRs and Preshared Keys from the current configuration file for the VPN
# Create new VPN using the same values for Inside Tunnel IP CIDRs and Preshared Keys
    getInsideIpCidr ${vpn[$counter]}
	
    pskList=(`aws ec2 describe-vpn-connections --vpn-connection-ids ${vpn[$counter]} --region $region | grep CustomerGatewayConfiguration | grep -oE "[a-zA-Z0-9_.]{32}"`)
    
    echo ""
    echo "Creating new VPN on VGW $newVgw as a replacement to Classic VPN ${vpn[$counter]}"
    echo "" >> $migData
    echo `date` >> $migData
	
    newVpn=`aws ec2 create-vpn-connection --type ipsec.1 --customer-gateway-id ${cgw[$counter]} --vpn-gateway-id $newVgw --options "{\"StaticRoutesOnly\":false,\"TunnelOptions\":[{\"TunnelInsideCidr\":"\"${insideIpCidrList[0]}\"",\"PreSharedKey\":"\"${pskList[0]}\""},{\"TunnelInsideCidr\":"\"${insideIpCidrList[1]}\"",\"PreSharedKey\":"\"${pskList[1]}\""}]}" --region $region | grep "VpnConnectionId" | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
    echo "New VPN to replace Classic VPN:${vpn[$counter]} - $newVpn" >> $migData
    echo "" >> $migData
    echo "Created new VPN $newVpn"
    echo ""
    ;;
   1)
# Create a BGP VPN with auto-generated Inside Tunnel IP CIDRs and auto-generated Preshared Keys
    echo ""
    echo "Creating new VPN on VGW $newVgw as a replacement to Classic VPN ${vpn[$counter]}"
    echo "" >> $migData
    echo `date` >> $migData
	
    newVpn=`aws ec2 create-vpn-connection --type ipsec.1 --customer-gateway-id ${cgw[$counter]} --vpn-gateway-id $newVgw --region $region | grep "VpnConnectionId" | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
    echo "New VPN to replace Classic VPN:${vpn[$counter]} - $newVpn" >> $migData
    echo "" >> $migData
    echo "Created new VPN $newVpn"
    echo ""

# Get the Inside Tunnel IP CIDRs from the current configuration file for the new VPN
# Add the Inside Tunnel IP CIDRs to the usedTunnel array
	getInsideIpCidr $newVpn
	
    ;;
   2)
# Create a BGP VPN with manually entered Inside Tunnel IP CIDRs and manually generated Preshared Keys
# For Inside Tunnel IP CIDRs, run all the checks to ensure sanity of the CIDRs
# For Preshared Keys, run all the checks to ensure sanity of the keys

# Inside Tunnel IP CIDR for Tunnel 1
    echo ""
    echo "Enter the Inside Tunnel IP CIDR for tunnel 1:"
    read tunnelF
    
# Check 1 - Inside Tunnel IP CIDR is not being used on the same VGW
# Check 2 - Format is 169.254.x.x/30
# Check 3 - Not allowed CIDRs - 169.254.0.0/30, 169.254.1.0/30, 169.254.2.0/30, 169.254.3.0/30, 169.254.4.0/30, 169.254.5.0/30, 169.254.169.252/30
# Check 4 - Valid IP address (3rd and 4th octet is not more than 255)
# Argument 1 - CIDR entered
# Argument 2 - To specify for which tunnel is the CIDR entered
    checkInsideIpCidr $tunnelF tunnel1
	
# Preshared Key for Tunnel 1
    echo ""
    echo "Enter the Preshared Key for tunnel 1:"
    read preF

# Make sure that the Preshared Key is as per the required format
# Argument 1 - PSK entered
# Argument 2 - To specify for which tunnel is the PSK entered
    checkPsk $preF tunnel1
  
# Inside Tunnel IP CIDR for Tunnel 2  
    echo ""
    echo "Enter the Inside Tunnel IP CIDR for tunnel 2:"
    read tunnelS
    
# Check 1 - Inside Tunnel IP CIDR is not being used on the same VGW
# Check 2 - Format is 169.254.x.x/30
# Check 3 - Not allowed CIDRs - 169.254.0.0/30, 169.254.1.0/30, 169.254.2.0/30, 169.254.3.0/30, 169.254.4.0/30, 169.254.5.0/30, 169.254.169.252/30
# Check 4 - Valid IP address (3rd and 4th octet is not more than 255)
# Argument 1 - CIDR entered
# Argument 2 - To specify for which tunnel is the CIDR entered
    checkInsideIpCidr $tunnelS tunnel2

# Preshared Key for Tunnel 2
    echo ""
    echo "Enter the Preshared Key for tunnel 2:"
    read preS

# Make sure that the Preshared Key is as per the required format
# Argument 1 - PSK entered
# Argument 2 - To specify for which tunnel is the PSK entered
    checkPsk $preS tunnel2
	
    echo ""
    echo "Creating new VPN on VGW $newVgw as a replacement to Classic VPN ${vpn[$counter]}"
    echo "" >> $migData
    echo `date` >> $migData
	
    newVpn=`aws ec2 create-vpn-connection --type ipsec.1 --customer-gateway-id ${cgw[$counter]} --vpn-gateway-id $newVgw --options "{\"StaticRoutesOnly\":false,\"TunnelOptions\":[{\"TunnelInsideCidr\":"\"$tunnelF\"",\"PreSharedKey\":"\"$preF\""},{\"TunnelInsideCidr\":"\"$tunnelS\"",\"PreSharedKey\":"\"$preS\""}]}" --region $region | grep "VpnConnectionId" | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
    echo "New VPN to replace Classic VPN:${vpn[$counter]} - $newVpn" >> $migData
    echo "" >> $migData
    echo "Created new VPN $newVpn"
    echo ""
    ;;
   3)
# Create a BGP VPN tunnel with manually entered Inside Tunnel IP CIDRs and auto-generated Preshared Keys
# For Inside Tunnel IP CIDRs, run all the checks to ensure sanity of the CIDRs

# Inside Tunnel IP CIDR for Tunnel 1
    echo ""
    echo "Enter the Inside Tunnel IP CIDR for tunnel 1:"
    read tunnelF
    
# Check 1 - Inside Tunnel IP CIDR is not being used on the same VGW
# Check 2 - Format is 169.254.x.x/30
# Check 3 - Not allowed CIDRs - 169.254.0.0/30, 169.254.1.0/30, 169.254.2.0/30, 169.254.3.0/30, 169.254.4.0/30, 169.254.5.0/30, 169.254.169.252/30
# Check 4 - Valid IP address (3rd and 4th octet is not more than 255)
# Argument 1 - CIDR entered
# Argument 2 - To specify for which tunnel is the CIDR entered
    checkInsideIpCidr $tunnelF tunnel1

# Inside Tunnel IP CIDR for Tunnel 2
    echo ""
    echo "Enter the Inside Tunnel IP CIDR for tunnel 2:" 
    read tunnelS
    
# Check 1 - Inside Tunnel IP CIDR is not being used on the same VGW
# Check 2 - Format is 169.254.x.x/30
# Check 3 - Not allowed CIDRs - 169.254.0.0/30, 169.254.1.0/30, 169.254.2.0/30, 169.254.3.0/30, 169.254.4.0/30, 169.254.5.0/30, 169.254.169.252/30
# Check 4 - Valid IP address (3rd and 4th octet is not more than 255)
# Argument 1 - CIDR entered
# Argument 2 - To specify for which tunnel is the CIDR entered
    checkInsideIpCidr $tunnelS tunnel2
	
    echo ""
    echo "Creating new VPN on VGW $newVgw as a replacement to Classic VPN ${vpn[$counter]}"
    echo "" >> $migData
    echo `date` >> $migData
	
    newVpn=`aws ec2 create-vpn-connection --type ipsec.1 --customer-gateway-id ${cgw[$counter]} --vpn-gateway-id $newVgw --options "{\"StaticRoutesOnly\":false,\"TunnelOptions\":[{\"TunnelInsideCidr\":"\"$tunnelF\""},{\"TunnelInsideCidr\":"\"$tunnelS\""}]}" --region $region | grep "VpnConnectionId" | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
    echo "New VPN to replace Classic VPN:${vpn[$counter]} - $newVpn" >> $migData
    echo "" >> $migData
    echo "Created new VPN $newVpn"
    echo ""
    ;;
   4)
# Create static VPN with manually entered Preshared Keys and auto-generated Inside Tunnel IP CIDRs
# For Preshared Keys, run all the checks to ensure sanity of the keys

# Preshared Key for Tunnel 1
    echo ""
    echo "Enter the Preshared Key for tunnel 1:"
    read preF

# Make sure that the Preshared Key is as per the required format
# Argument 1 - PSK entered
# Argument 2 - To specify for which tunnel is the PSK entered
    checkPsk $preF tunnel1

# Preshared Key for Tunnel 2 
    echo ""
    echo "Enter the Preshared Key for tunnel 2:"
    read preS

# Make sure that the Preshared Key is as per the required format
# Argument 1 - PSK entered
# Argument 2 - To specify for which tunnel is the PSK entered
    checkPsk $preS tunnel2
	
    echo ""
    echo "Creating new VPN on VGW $newVgw as a replacement to Classic VPN ${vpn[$counter]}"
    echo "" >> $migData
    echo `date` >> $migData
	
    newVpn=`aws ec2 create-vpn-connection --type ipsec.1 --customer-gateway-id ${cgw[$counter]} --vpn-gateway-id $newVgw --options "{\"StaticRoutesOnly\":false,\"TunnelOptions\":[{\"PreSharedKey\":"\"$preF\""},{\"PreSharedKey\":"\"$preS\""}]}" --region $region | grep "VpnConnectionId" | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
    echo "$counter: New VPN to replace Classic VPN:${vpn[$counter]} - $newVpn" >> $migData
    echo "" >> $migData
    echo "Created new VPN $newVpn"
    echo ""
	
# Get the Inside Tunnel IP CIDRs from the current configuration file for the new VPN
# Add the Inside Tunnel IP CIDRs to the usedTunnel array
	getInsideIpCidr $newVpn
    ;;
   *)
    echo ""
    echo "Please enter a valid option"
    continue
    ;;
  esac
 fi
 counter=$[$counter + 1]
done
echo "################################################################################" >> $migData
echo "" >> $migData
