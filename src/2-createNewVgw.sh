# This script will create a new VGW with same configuration as the old one
# INPUT - Option to select if new VGW should have default ASN or custom ASN
# OUTPUT - New VGW
# ERROR CHECKS - 
# VGW Per Region Limit (Default 5 per Region) 

#! /bin/bash

# This function will check if the VGW Limit is hit
# Default - 5 VGWs per Region
# If Limit is hit, exit the script
vgwLimitHit ()
{
# If VGW Per Region Limit is hit, log it and exit the script
  `rm -rf temp$oldVgw.txt`
  echo ""
  echo "VGW Limit Hit! Please delete unused VGWs or increase the limit of VGWs per Region"
  echo "Exiting the script"
  echo "VGW Limit hit" >> $migData
  echo "################################################################################" >> $migData
  exit 1
} 

# This function will check if a new VGW is already created
# If new VGW exists, exit the script
checkVgwExists ()
{
 dataFile=$1
 numNewVgw=`cat $dataFile | grep "New VGW:" | wc -l`
 numDeletedVgw=`cat $dataFile | grep "Deleted VGW:" | wc -l`
 newVgwId=`cat $dataFile | grep "New VGW:" | tail -n 1 | cut -d":" -f2`
 if [ $numNewVgw -gt 0 ]; then
  if [ $numNewVgw -gt $numDeletedVgw ]; then
   echo ""
   echo "You have already created a new VGW: $newVgwId"
   echo "Exiting the script"
   exit 1
  fi
 fi   
}

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
# If the VGW exists already, then log it and exit the script
res="resources.txt"
numOldVgw=`cat $res | cut -d":" -f2 | wc -l`
if [ $numOldVgw -eq 1 ]; then
 vgw=`cat $res |  cut -d":" -f2 | sed 's/ //g'`
 migData="migration_$vgw.txt"
 checkVgwExists $migData
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
 checkVgwExists $migData
fi

# Get the AWS Region from the stored data
region=`cat $migData | grep "AWS Region:" | tail -n 1 | cut -d":" -f2`

# Create VGW with custom Amazon-side BGP ASN - 16-bit (64512-65534) OR 32-bit (4200000000-4294967294)
# OR create VGW with default Amazon-side BGP ASN
# If VGW Limit is Hit - Exit the script
echo ""
echo "Do you want to create the new VGW with custom Amazon Side BGP ASN or default Amazon Side BGP ASN?"
echo "1 - 16-bit Custom Amazon Side BGP ASN [64512 - 65534]"
echo "2 - 32-bit Custom Amazon Side BGP ASN [4200000000 - 4294967294]"
echo "3 - Default Amazon Side BGP ASN"
read option
while [ 1 ]; do
 case $option in
  1)
   echo ""
   echo "Enter the 16-bit Amazon Side BGP ASN:"
   read amznAsn
   while [ 1 ]; do
    if (( $amznAsn < 64512 || $amznAsn > 65534 )); then
     echo ""
     echo "Please enter a valid 16-bit Amazon Side BGP ASN:"
     read amznAsn
    else
     break
    fi
   done
   echo ""
   echo "Creating new VGW with Amazon Side BGP ASN $amznAsn"
   echo "Creating new VGW" >> $migData
   echo "" >> $migData
   echo `date` >> $migData
   `aws ec2 create-vpn-gateway --type ipsec.1 --amazon-side-asn $amznAsn --region $region > temp$oldVgw.txt`
   stat=`echo $?`

# If VGW Per Region Limit is hit, log it and exit the script
   if [ $stat -eq 255 ]; then
    vgwLimitHit
   else
   
# If VGW is created successfully, log the new VGW Id
    newVgw=`cat temp$oldVgw.txt | grep VpnGatewayId | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
    `rm -rf temp$oldVgw.txt`
    echo "New VGW: $newVgw" >> $migData
    echo "################################################################################" >> $migData
	echo "" >> $migData
    echo ""
    echo "New VGW $newVgw created with Amazon Side BGP ASN $amznAsn. Please check $migData for more information."
    break
   fi
   ;;
  2)
   echo ""
   echo "Enter the 32-bit Amazon Side BGP ASN:"
   read amznAsn
   while [ 1 ]; do
    if (( $amznAsn < 4200000000 || $amznAsn > 4294967294 )); then
     echo ""
     echo "Please enter a valid 32-bit Amazon Side BGP ASN:"
     read amznAsn
    else
     break
    fi
   done
   echo ""
   echo "Creating new VGW with Amazon Side BGP ASN $amznAsn"
   echo "Creating new VGW" >> $migData
   echo "" >> $migData
   echo `date` >> $migData
   `aws ec2 create-vpn-gateway --type ipsec.1 --amazon-side-asn $amznAsn --region $region > temp$oldVgw.txt`
   stat=`echo $?`

# If VGW Per Region Limit is hit, log it and exit the script
   if [ $stat -eq 255 ]; then
    vgwLimitHit
   else

# If VGW is created successfully, log the new VGW Id
    newVgw=`cat temp$oldVgw.txt | grep VpnGatewayId | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
    `rm -rf temp$oldVgw.txt`
    echo "New VGW: $newVgw" >> $migData
    echo "################################################################################" >> $migData
	echo "" >> $migData
    echo ""
    echo "New VGW $newVgw created with Amazon Side BGP ASN $amznAsn. Please check $migData for more information."
    break
   fi
   ;;
  3)
   echo ""
   echo "Creating new VGW with default Amazon Side BGP ASN"
   echo "Creating new VGW" >> $migData
   echo "" >> $migData
   echo `date` >> $migData
   `aws ec2 create-vpn-gateway --type ipsec.1 --region $region > temp$oldVgw.txt`
   stat=`echo $?`

# If VGW Per Region Limit is hit, log it and exit the script
    if [ $stat -eq 255 ]; then
     vgwLimitHit
    else

# If VGW is created successfully, log the new VGW Id
     newVgw=`cat temp$oldVgw.txt | grep VpnGatewayId | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`
     echo "New VGW: $newVgw" >> $migData
     `rm -rf temp$oldVgw.txt`
     echo "################################################################################" >> $migData
     echo "" >> $migData
     echo ""
     echo "New VGW $newVgw created. Please check $migData for more information"
     break
    fi
    ;;
  *)
   echo ""
   echo "Please enter a valid option"
   read option
   ;;
 esac
done
