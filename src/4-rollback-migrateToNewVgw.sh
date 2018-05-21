# This script will perform the migration rollback activity -
# Detach the New VGW, Attach Old VGW, Enable Route Propagation if it was enabled, Update manually entered VGW routes
# INPUT - NONE
# OUTPUT - Old VGW attached to the VPC, Route tables updated
# ERROR CHECKS - NONE

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

# Depending on the old VGW, select the migration data file
# If there is only 1 VGW in resources.txt, use the migration data file
# If there are multiple VGWs in resources.txt, ask to enter the VGW to proceed, and then select the migration data file
# Resources.txt - File to store the old VGWs
res="resources.txt"
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

# Get the AWS Region, Old VGW Id, and new VGW Id from the stored data
region=`cat $migData | grep "AWS Region:" | tail -n 1 | tr -s " " | cut -d":" -f2`
oldVgw=`cat $migData | grep "Old VGW:" | tail -n 1 | cut -d":" -f2 | tr -s " " | cut -d" " -f2`
newVgw=`cat $migData | grep "New VGW:" | tail -n 1 | cut -d":" -f2 | tr -s " " | cut -d" " -f2`

declare -a routeTables
declare -a routeTablesRP
declare -a routeTablesNoRP
declare -a routes
vpc=`aws ec2 describe-vpn-gateways --vpn-gateway-ids $newVgw --region $region | grep VpcId | cut -d":" -f2 | sed 's/"//g' | tr -s " " | cut -d" " -f2`

# Determine the route-tables in the VPC
routeTables=(`aws ec2 describe-route-tables --region $region --filters Name=vpc-id,Values=$vpc | grep "rtb-" | grep "," | cut -d":" -f2 | sed 's/"//g' | sed 's/,//g'`)
numRouteTables=${#routeTables[@]}
counter=0

# Find route tables with RP enabled and RP disabled
# Go through all the route tables in the VPC and sort them into route tables with RP enabled and route tables with RP disabled
echo "Checking route tables in $vpc"
while [ $counter -lt $numRouteTables ]; do
 isRouteProp=`aws ec2 describe-route-tables --route-table-ids ${routeTables[$counter]} --region $region | grep -A2 PropagatingVgws | grep "vgw-" | wc -l`
 if [ $isRouteProp == 1 ]; then
  routeTablesRP+=(${routeTables[$counter]})
 else
  routeTablesNoRP+=(${routeTables[$counter]})
 fi
 counter=$[$counter + 1]
done

echo "" >> $migData
echo "Route Tables with Route Propagation Enabled:" >> $migData
echo ${routeTablesRP[@]} >> $migData
echo "" >> $migData
echo "Route Tables with Route Propagation Disabled:" >> $migData
echo ${routeTablesNoRP[@]} >> $migData

# Detach the new VGW and attach the old VGW
# Wait for new VGW to detach and old VGW to attach, before going further
# If the new VGW is already detached or does not exist any more, log and proceed further
# Two checks for detached New VGW:
# isDetached1 - VGW is detached recently. VPCAttachments show the VGW as detached
# isDetached2 - VGW is detached a long-time back. VPCAttachments do not show any information about the VGW
isDetached1=`aws ec2 describe-vpn-gateways --vpn-gateway-ids $newVgw --region $region | grep "detached" | wc -l`
isDetached2=`aws ec2 describe-vpn-gateways --vpn-gateway-ids $newVgw --region $region | grep -E "\"VpcAttachments\": \[\]," | wc -l`
if (( $isDetached1 == 1 || $isDetached2 == 1 )); then
 echo ""
 echo "New VGW $newVgw is already detached"
else
 echo ""
 echo "Detaching new VGW $newVgw from VPC $vpc"
 `aws ec2 detach-vpn-gateway --vpn-gateway-id $newVgw --vpc-id $vpc --region $region`
 while [ $isDetached1 -lt 1 ]; do
  sleep 5
  isDetached1=`aws ec2 describe-vpn-gateways --vpn-gateway-ids $newVgw --region $region | grep "detached" | wc -l`
 done
 echo "New VGW $newVgw detached"
 echo "" >> $migData
 echo `date` >> $migData
 echo "New VGW $newVgw detached" >> $migData
fi

# If the old VGW is already attached, log and proceed further
# If not, attach the old VGW
isAttached=`aws ec2 describe-vpn-gateways --vpn-gateway-ids $oldVgw --region $region | grep "attached" | wc -l`
if [ $isAttached == 1 ]; then
 echo ""
 echo "Old VGW $oldVgw is already attached"
else
 echo "Attaching old VGW $oldVgw to VPC $vpc"
 `aws ec2 attach-vpn-gateway --vpn-gateway-id $oldVgw --vpc-id $vpc --region $region &> /dev/null`
 while [ $isAttached -lt 1 ]; do
  sleep 30
  isAttached=`aws ec2 describe-vpn-gateways --vpn-gateway-ids $oldVgw --region $region | grep "attached" | wc -l`
 done
 echo "Old VGW $oldVgw attached"
 echo "" >> $migData
 echo `date` >> $migData
 echo "Old VGW $oldVgw attached" >> $migData
 echo ""
fi

# Enable RP in the route tables which had RP enabled with the New VGW
# Go through the list of route tables which had RP enabled, and re-enable RP with the new VGW
rpCounter=0
numRpRt=${#routeTablesRP[@]}
if [ $numRpRt -gt 0 ]; then
 echo ""
 echo "There are $numRpRt route tables in $vpc with Route Propagation enabled"
fi
while [ $rpCounter -lt $numRpRt ]; do
 echo "Enabling route propagation in the route-table ${routeTablesRP[$rpCounter]} with VGW $oldVgw"
 `aws ec2 enable-vgw-route-propagation --route-table-id ${routeTablesRP[$rpCounter]} --gateway-id $oldVgw --region $region`
 echo "Route Propagation enabled in the route-table ${routeTablesRP[$rpCounter]}"
 echo "" >> $migData
 echo `date` >> $migData
 echo "Route Propagation enabled in the route-table ${routeTablesRP[$rpCounter]}" >> $migData
 rpCounter=$[$rpCounter + 1]
 echo "$rpCounter of $numRpRt done"
 echo ""
done

# If RP is disabled, check the routes with Target as New VGW, and replace the Target with Old VGW
noRpCounter=0
numNoRpRt=${#routeTablesNoRP[@]}
if [ $numNoRpRt -gt 0 ]; then
 echo ""
 echo "There are $numNoRpRt route tables in $vpc with Route Propagation disabled"
fi
while [ $noRpCounter -lt $numNoRpRt ]; do
 echo "Checking route-table ${routeTablesNoRP[$noRpCounter]} for manually entered routes with Target as $newVgw"
 routes=(`aws ec2 describe-route-tables --route-table-ids ${routeTablesNoRP[$noRpCounter]} --region $region | grep -A1 $newVgw | grep DestinationCidrBlock | cut -d":" -f2 | sed "s/,//g" | sed 's/"//g'`)
 numRoutes=${#routes[@]}
 rcounter=0
 echo "Replacing the Target $newVgw with $oldVgw"
 while [ $rcounter -lt $numRoutes ]; do
  `aws ec2 replace-route --route-table-id ${routeTablesNoRP[$noRpCounter]} --destination-cidr-block ${routes[$rcounter]} --gateway-id $oldVgw --region $region`
  rcounter=$[$rcounter + 1]
 done
 echo "Updated route-table ${routeTablesNoRP[$noRpCounter]}"
 echo "" >> $migData
 echo `date` >> $migData
 echo "Updated route-table ${routeTablesNoRP[$noRpCounter]}" >> $migData
 noRpCounter=$[$noRpCounter + 1]
 echo "$noRpCounter of $numNoRpRt done"
 echo ""
done 

echo "################################################################################" >> $migData
echo "" >> $migData
echo ""
echo "Migration Rollback Completed!"
