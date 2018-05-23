## AWS Vpn Migration Scripts

AWS VPN Migration scripts that provide a simple way to migrate from a Classic VPN to an AWS VPN connection, using public APIs.

## License

This library is licensed under the Amazon Software License.

## Scripts Used for Migration

1-describeOldVgw.sh: This script will get the details of the old VGW and AWS Classic VPN on the VGW

2-createNewVgw.sh: This script will create a new VGW with custom ASN (16-bit or 32-bit) or Amazon default ASN

3-createAwsVpn.sh: This script will create a new AWS VPN for each AWS Classic VPN

4-migrateToNewVgw.sh: This script will perform the migration from an AWS Classic VPN to AWS VPN. The migration includes detaching the old VGW from the VPC, attaching the new VGW to the VPC, enabling Route Propagation with the new VGW, modifying the Targets of manually added routes from old VGW to new VGW

5-deleteClassicVpnAndVgw.sh: This script will delete the AWS Classic VPN and the old VGW

3-rollback-createAwsVpn.sh: This script will rollback the creation of the new AWS VPN and new VGW

4-rollback-migrateToNewVgw.sh: This script will rollback the migration from AWS Classic VPN to AWS VPN. This will include detaching the new VGW from the VPC, attaching the old VGW to the VPC, enabling Route Propagation with the old VGW, modifying the Targets of manually added route

## Prerequisites

a.	Make sure that the latest version of AWS CLI is installed. Please refer to this link to install or upgrade AWS CLI -> https://docs.aws.amazon.com/cli/latest/userguide/installing.html

b.	Make sure that you have configured AWS CLI with the correct Credentials. Please refer to this link to configure AWS CLI -> https://docs.aws.amazon.com/cli/latest/userguide/cli-config-files.html

## Usage Instructions

Once you have the pre-requisites in place, you can run the scripts as follows ->

sh /path/to/script/scriptname.sh

OR

cd  /path/to/script/

./scriptname.sh

## Migration Process

1. Run the script "1-describeOldVgw.sh" to store the details of the old VGW and the AWS Classic VPN on the VGW. You will have to provide the AWS Region in which you have the AWS Classic VPN connection and the old VGW Id.

2. Run the script "2-createNewVgw.sh" to create a new VGW with either a custom ASN or Amazon default ASN. If you select custom ASN, you have to provide a valid 16-bit or 32-bit private ASN.

3. Run the script "3-createAwsVpn.sh" to create a new AWS VPN connection for each AWS Classic VPN connection. In order to create a VPN, you can select from one of the following five options:

a. Create AWS VPN with the same values of Inside Tunnel IP CIDRs and Preshared Keys as the corresponding AWS Classic VPN

b. Create AWS VPN with auto-generated Inside Tunnel IP CIDRs and Preshared Keys

c. Create AWS VPN with manually entered Inside Tunnel IP CIDRs and Preshared Keys

d. Create AWS VPN with manually entered Inside Tunnel IP CIDRs and auto-generated Preshared Keys

e. Create AWS VPN with auto-generated Inside Tunnel IP CIDRs and manually entered Preshared Keys

Please refer to Requirements for Inside Tunnel IP CIDRs and Preshared Keys.

Note: If you need to delete the new AWS VPN and the new VGW, you can run the script "3-rollback-createAwsVpn.sh".

4. Once the new AWS VPN has been created, go the Amazon VPC Console at https://console.aws.amazon.com/vpc/. Select the new AWS VPN and choose Download Configuration. Download the appropriate configuration file for your customer gateway device. Use the configuration file to configure VPN tunnels on your customer gateway device. For examples, see the Amazon VPC Network Administrator Guide. Do not enable the tunnels yet. Contact your vendor if you need guidance on keeping the newly configured tunnels disabled.

5. Once you are ready to migrate from the AWS Classic VPN to AWS VPN, run the script "4-migrateToNewVgw.sh". This script will detach the old VGW from the VPC and attach the new VGW to the VPC. If you had Route Propagation enabled for your route tables, this script will enable it with the new VGW. If you had Route Propagation disabled and had manually entered routes via old VGW, this script will modify the routes to point to the new VGW.

Note: Connectivity is interrupted until the new virtual private gateway is attached and the new AWS VPN connection is active. 

6. Enable the new tunnels on your customer gateway device and disable the old tunnels. To bring the tunnel up, you must initiate the connection from your local network.

Note: If you need to revert to your previous configuration, you can run the script "4-rollback-migrateToNewVgw.sh". This script will detach the new VGW from the VPC and attach the old VGW to the VPC. If you had Route Propagation enabled for your route tables, this script will enable it with the old VGW. If you had Route Propagation disabled and had manually entered routes via new VGW, this script will modify the routes to point to the old VGW.

Note: If you need to delete the new AWS VPN and the new VGW, you can run the script "3-rollback-createAwsVpn.sh".

7. If you no longer need your AWS Classic VPN connection and do not want to continue incurring charges for it, remove the previous tunnel configurations from your customer gateway device, and delete the AWS Classic VPN connection. To do this, run the script "5-deleteClassicVpnAndVgw.sh".

Important: After you've deleted the AWS Classic VPN connection, you cannot revert or migrate your new AWS VPN connection back to an AWS Classic VPN connection.
