#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

for OPT in "$@"
do
  case "$OPT" in
    '--stack-name' )
      if [ -z "$2" ]; then
          echo "option -f or --stack-name requires an argument -- $1" 1>&2
          exit 1
      fi
      STACK_NAME="$2"
      shift 2
      ;;
  esac
done
if [ -z "${STACK_NAME}" ] ; then
  echo "ERROR: Option --stack-name needs to be specified"
  exit 1
fi

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
SSH_LOCATION="$(curl ifconfig.co 2> /dev/null)/32"

REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

################################
# Step 1: Create the VPCs
################################
for REGION in ${REGIONS}
do 
  if ! aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --region "${REGION}" > /dev/null 2>&1; then
    echo "Creating a CloudFormation stack=${STACK_NAME} for region=${REGION}"

    # If it fails, an error message is displayed and it continues to the next REGION
    aws cloudformation create-stack \
      --stack-name "${STACK_NAME}" \
      --template-body file://cloudformation-vpc.yaml \
      --capabilities CAPABILITY_NAMED_IAM \
      --parameters ParameterKey=SSHLocation,ParameterValue="${SSH_LOCATION}" \
                    ParameterKey=AWSAccountId,ParameterValue="${AWS_ACCOUNT_ID}" \
      --region "${REGION}" \
      --output text
  else
    echo "Cloudformatoin stack in ${REGION} already exists"
  fi
done 

###################################################
# Step 2: Wait on CloudFormation VPC stack creation
###################################################
for REGION in ${REGIONS}
do
  echo "Waiting until the CloudFormation stack is CREATE_COMPLETE for ${REGION}"
  if ! aws cloudformation wait stack-create-complete --stack-name "${STACK_NAME}" --region "${REGION}"; then
    >&2 echo "ERROR: CloudFormation wait failed for ${REGION}"
    exit 1
  fi
done

################################################
# Step 3: Create VPC Peering in all the regions
################################################
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

for REGION1 in ${REGIONS}
do
  for REGION2 in ${REGIONS}
  do
    if [ "${REGION1}" != "${REGION2}" ] ; then
      ./create-vpc-peering.sh \
        --aws-account "${AWS_ACCOUNT_ID}" \
        --stack-name "${STACK_NAME}" \
        --region1 "${REGION1}" \
        --region2 "${REGION2}"
    fi      
  done
done

########################################################
# Step 4: Generate the json file used in the
# later testing phase
#######################################################

./generate-vpc-json.sh --stack-name "${STACK_NAME}" > ../vpc.json