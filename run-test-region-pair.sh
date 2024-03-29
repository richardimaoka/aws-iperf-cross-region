#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

######################################
# 1.1 Parse options
######################################
for OPT in "$@"
do
  case "$OPT" in
    '--stack-name' )
      if [ -z "$2" ]; then
          echo "option --stack-name requires an argument -- $1" 1>&2
          exit 1
      fi
      STACK_NAME="$2"
      shift 2
      ;;
    '--source-region' )
      if [ -z "$2" ]; then
          echo "option --source-region requires an argument -- $1" 1>&2
          exit 1
      fi
      SOURCE_REGION="$2"
      shift 2
      ;;
    '--target-region' )
      if [ -z "$2" ]; then
          echo "option --target-region requires an argument -- $1" 1>&2
          exit 1
      fi
      TARGET_REGION="$2"
      shift 2
      ;;
    '--test-uuid' )
      if [ -z "$2" ]; then
          echo "option --test-uuid requires an argument -- $1" 1>&2
          exit 1
      fi
      TEST_EXECUTION_UUID="$2"
      shift 2
      ;;
    '--s3-bucket' )
        if [ -z "$2" ]; then
            echo "option --s3-bucket requires an argument -- $1" 1>&2
            exit 1
        fi
        S3_BUCKET_NAME="$2"
        shift 2
        ;;
    -*)
      echo "illegal option -- $1" 1>&2
      exit 1
      ;;
  esac
done

######################################
# 1.2 Validate options
######################################
if [ -z "${STACK_NAME}" ] ; then
  >&2 echo "ERROR: option --stack-name needs to be passed"
  ERROR="1"
fi
if [ -z "${SOURCE_REGION}" ] ; then
  >&2 echo "ERROR: option --source-region needs to be passed"
  ERROR="1"
fi
if [ -z "${TARGET_REGION}" ] ; then
  >&2 echo "ERROR: option --target-region needs to be passed"
  ERROR="1"
fi
if [ -z "${TEST_EXECUTION_UUID}" ] ; then
  >&2 echo "ERROR: option --test-uuid needs to be passed"
  ERROR="1"
fi
if [ -z "${S3_BUCKET_NAME}" ] ; then
  >&2 echo "ERROR: option --s3-bucket needs to be passed"
  ERROR="1"
fi
if [ -n "${ERROR}" ] ; then
  exit 1
fi

######################################
# 2.0. Check if everything is ready
######################################
if [ ! -f input.json ] ; then
  >&2 echo "ERROR: input.json is not generated. Run generate-input-json.sh to generate it."
  exit 1
elif ! INPUT_JSON=$(jq -r "." < input.json); then
  >&2 echo "ERROR: Failed to read input JSON from input.json"
  exit 1
fi

######################################
# 2.1. Create the source EC2 instance
######################################
SOURCE_INSTANCE_TYPE=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".instance_type")
SOURCE_IMAGE_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".image_id")
SOURCE_SECURITY_GROUP_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".security_group")
SOURCE_SUBNET_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".subnet_id")
SOURCE_INSTANCE_PROFILE=$(echo "${INPUT_JSON}" | jq -r ".\"$SOURCE_REGION\".instance_profile")

echo "Starting EC2 in ${SOURCE_REGION}"
if ! SOURCE_OUTPUTS=$(aws ec2 run-instances \
  --image-id "${SOURCE_IMAGE_ID}" \
  --instance-type "${SOURCE_INSTANCE_TYPE}" \
  --key-name "demo-key-pair" \
  --iam-instance-profile Name="${SOURCE_INSTANCE_PROFILE}" \
  --network-interfaces \
    "AssociatePublicIpAddress=true,DeviceIndex=0,Groups=${SOURCE_SECURITY_GROUP_ID},SubnetId=${SOURCE_SUBNET_ID}" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=experiment-name,Value=${STACK_NAME}}]" \
  --user-data file://user-data.txt \
  --region "${SOURCE_REGION}"
) ; then
  echo "Failed to start EC2 in ${SOURCE_REGION}"
  exit 1
fi

SOURCE_INSTANCE_ID=$(echo "${SOURCE_OUTPUTS}" | jq -r ".Instances[].InstanceId")

######################################
# 2.2. Create the target EC2 instance
######################################
TARGET_INSTANCE_TYPE=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".instance_type")
TARGET_IMAGE_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".image_id")
TARGET_SECURITY_GROUP_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".security_group")
TARGET_SUBNET_ID=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".subnet_id")
TARGET_INSTANCE_PROFILE=$(echo "${INPUT_JSON}" | jq -r ".\"$TARGET_REGION\".instance_profile")

echo "Starting EC2 in ${TARGET_REGION}"
if ! TARGET_OUTPUTS=$(aws ec2 run-instances \
  --image-id "${TARGET_IMAGE_ID}" \
  --instance-type "${TARGET_INSTANCE_TYPE}" \
  --key-name "demo-key-pair" \
  --iam-instance-profile Name="${TARGET_INSTANCE_PROFILE}" \
  --network-interfaces \
    "AssociatePublicIpAddress=true,DeviceIndex=0,Groups=${TARGET_SECURITY_GROUP_ID},SubnetId=${TARGET_SUBNET_ID}" \
  --tag-specifications \
    "ResourceType=instance,Tags=[{Key=experiment-name,Value=${STACK_NAME}}]" \
  --user-data file://user-data.txt \
  --region "${TARGET_REGION}"
) ; then
  echo "Failed to start EC2 in ${TARGET_REGION}"
  exit 1
fi

TARGET_INSTANCE_ID=$(echo "${TARGET_OUTPUTS}" | jq -r ".Instances[].InstanceId")
TARGET_PRIVATE_IP=$(echo "${TARGET_OUTPUTS}" | jq -r ".Instances[].NetworkInterfaces[].PrivateIpAddress")

##############################################
# 2.3. Wait for the EC2 instances to be ready
##############################################
echo "Waiting for the EC2 instances to be status = ok: source = ${SOURCE_INSTANCE_ID}(${SOURCE_REGION}) and target = ${TARGET_INSTANCE_ID}(${TARGET_REGION})"
if ! aws ec2 wait instance-status-ok --instance-ids "${SOURCE_INSTANCE_ID}" --region "${SOURCE_REGION}" ; then
  >&2 echo "ERROR: failed to wait on the source EC2 instance = ${SOURCE_INSTANCE_ID}"
  exit 1
elif ! aws ec2 wait instance-status-ok --instance-ids "${TARGET_INSTANCE_ID}" --region "${TARGET_REGION}" ; then
  >&2 echo "ERROR: failed to wait on the source EC2 instance = ${TARGET_INSTANCE_ID}"
  exit 1
fi

######################################################
# 3 Send the command and sleep to wait
######################################################
echo "Sending command to the source EC2=${SOURCE_INSTANCE_ID}(${SOURCE_REGION})"
COMMANDS="/home/ec2-user/aws-iperf-cross-region/iperf-target.sh"
COMMANDS="${COMMANDS} --target-region ${TARGET_REGION}"
COMMANDS="${COMMANDS} --target-ip ${TARGET_PRIVATE_IP}"
COMMANDS="${COMMANDS} --test-uuid ${TEST_EXECUTION_UUID}"
COMMANDS="${COMMANDS} --s3-bucket ${S3_BUCKET_NAME}"
if ! aws ssm send-command \
  --instance-ids "${SOURCE_INSTANCE_ID}" \
  --document-name "AWS-RunShellScript" \
  --comment "aws-iperf command to run iperf to the target iperf server" \
  --parameters commands=["${COMMANDS}"] \
  --region "${SOURCE_REGION}" > /dev/null ; then
  >&2 echo "ERROR: failed to send command to = ${SOURCE_INSTANCE_ID}"
fi

# No easy way to signal the end of the command, so sleep to wait enough
sleep 90s

######################################################
# 4.3 Terminate the EC2 instances
######################################################
echo "Terminate the EC2 instances source=${SOURCE_INSTANCE_ID}(${SOURCE_REGION}) target=${TARGET_INSTANCE_ID}(${TARGET_REGION})"
if ! aws ec2 terminate-instances --instance-ids "${SOURCE_INSTANCE_ID}" --region "${SOURCE_REGION}" > /dev/null ; then
  >&2 echo "ERROR: failed terminate the source EC2 instance = ${SOURCE_INSTANCE_ID}"
  exit 1
fi
if ! aws ec2 terminate-instances --instance-ids "${TARGET_INSTANCE_ID}" --region "${TARGET_REGION}" > /dev/null ; then
  >&2 echo "ERROR: failed terminate the target EC2 instance = ${TARGET_INSTANCE_ID}"
  exit 1
fi