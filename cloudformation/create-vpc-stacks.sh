#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

############################################################
# Kill the child (background) processes on Ctrl+C = (SIG)INT
############################################################
# This script runs run-ec2-instance.sh in the background
# https://superuser.com/questions/543915/whats-a-reliable-technique-for-killing-background-processes-on-script-terminati/562804
trap 'kill -- -$$' INT

######################################
# 1.1 Parse options
######################################
STACK_NAME="IPerfCrossRegionExperiment"
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
    -*)
      echo "illegal option $1" 1>&2
      exit 1
      ;;
  esac
done

###########################################
# 2: Create the CloudFormation VPC stacks
###########################################
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
SSH_LOCATION="$(curl ifconfig.co 2> /dev/null)/32"

REGIONS=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)
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
      --output text &
  else
    echo "Cloudformation stack in ${REGION} already exists"
  fi
done 

###################################################
# 3: Wait on CloudFormation VPC stack creation
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
# 4: Create VPC Peering in all the regions
################################################
# ./generate-region-pairs.sh

while IFS= read -r REGION_PAIR
do
  REGION1=$(echo "${REGION_PAIR}" | awk '{print $1}')
  REGION2=$(echo "${REGION_PAIR}" | awk '{print $2}')

  ./create-vpc-peering.sh \
    --aws-account "${AWS_ACCOUNT_ID}" \
    --stack-name "${STACK_NAME}" \
    --region1 "${REGION1}" \
    --region2 "${REGION2}" &
done < region-pairs.txt

######################################
# 5. Wait until the children complete
######################################
echo "Wait until all the child processes are finished..."

#Somehow VARIABLE=$(jobs -p) gets empty. So, need to use a file.
TEMP_FILE=$(mktemp)
jobs -p > "${TEMP_FILE}"

# Read and go through the ${TEMP_FILE} lines
while IFS= read -r PID
do
  wait "${PID}"
done < "${TEMP_FILE}"

rm "${TEMP_FILE}"
echo "All the children finished!!"

########################################################
# 6: Generate the json file used in the
# later testing phase
#######################################################

./generate-whole-vpc-json.sh --stack-name "${STACK_NAME}" | jq "." > ../output.json