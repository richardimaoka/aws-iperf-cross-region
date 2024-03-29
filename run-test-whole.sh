#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

############################################################
# Kill the child (background) processes on Ctrl+C = (SIG)INT
############################################################
# This script runs run-ec2-instance.sh in the background
# https://superuser.com/questions/543915/whats-a-reliable-technique-for-killing-background-processes-on-script-terminati/562804
trap 'kill -- -$$' INT

TEST_EXECUTION_UUID=$(uuidgen)
S3_BUCKET_NAME="samplebucket-richardimaoka-sample-sample"
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
      '--s3-bucket' )
        if [ -z "$2" ]; then
            echo "option --s3-bucket requires an argument -- $1" 1>&2
            exit 1
        fi
        S3_BUCKET_NAME="$2"
        shift 2
        ;;
      '-f' | '--file-name' )
        if [ -z "$2" ]; then
            echo "option -f or --file-name requires an argument -- $1" 1>&2
            exit 1
        fi
        FILE_NAME="$2"
        shift 2
        ;;
    esac
done

#################################
# 1. Prepare the input json
#################################
if [ -z "${STACK_NAME}" ] ; then
  >&2 echo "ERROR: option --stack-name needs to be passed"
  ERROR="1"
fi
if [ -z "${FILE_NAME}" ] ; then
  >&2 echo "ERROR: option -f or --file-name needs to be passed"
  ERROR="1"
elif ! jq -r "." < "${FILE_NAME}"; then
  >&2 echo "ERROR: Failed to read input JSON from ${FILE_NAME}"
  ERROR="1"
fi
if [ -n "${ERROR}" ] ; then
  exit 1
fi

##############################################################
# 2. Prepare REGION_PAIRS for efficient loop in the next step
#############################################################
# The $REGION_PAIRS variable to hold text like below, delimited by new lines, split by a whitespace:
#   >ap-northeast-2 eu-west-2
#   >ap-northeast-2 eu-west-1
#   >ap-northeast-2 ap-northeast-1
#   >...
#   >sa-east-1 eu-north-1
#   >sa-east-1 eu-west-1
#   >...
REGIONS=$(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text)
REGIONS_INNER_LOOP=$(echo "${REGIONS}")
TEMPFILE=$(mktemp)
for REGION1 in $REGIONS
do
  # to avoid the same pair appear twice
  REGIONS_INNER_LOOP=$(echo "${REGIONS_INNER_LOOP}" | grep -v "${REGION1}")
  for REGION2 in $REGIONS_INNER_LOOP
  do
    echo "${REGION1} ${REGION2}" >> "${TEMPFILE}"
  done
done
REGION_PAIRS=$(cat "${TEMPFILE}")

######################################################
# 3. main loop
######################################################
# Pick up one region pair at a time
# REGION_PAIRS will remove the picked-up element at the end of an iteration
while PICKED_UP=$(echo "${REGION_PAIRS}" | shuf -n 1) && [ -n "${PICKED_UP}" ]
do
  SOURCE_REGION=$(echo "${PICKED_UP}" | awk '{print $1}')
  TARGET_REGION=$(echo "${PICKED_UP}" | awk '{print $2}')

  SOURCE_INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:experiment-name,Values=${STACK_NAME}" \
    --query "Reservations[*].Instances[?State.Name!='terminated'].InstanceId" \
    --output text \
    --region "${SOURCE_REGION}"
  )
  TARGET_INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:experiment-name,Values=${STACK_NAME}" \
    --query "Reservations[*].Instances[?State.Name!='terminated'].InstanceId" \
    --output text \
    --region "${TARGET_REGION}"
  )

  # Run run-ec2-instance.sh only when both SOURCE_REGION and TARGET_REGION has no EC2 running
  if [ -z "${SOURCE_INSTANCE_ID}" ] && [ -z "${TARGET_INSTANCE_ID}" ] ; then
    REMAINING=$(echo "${REGION_PAIRS}" | wc -l)
    echo "(${REMAINING})Running the EC2 instances in the source region=${SOURCE_REGION} and the target region=${TARGET_REGION}"
    ######################################################
    # Run in the background as it takes time, so that
    # the next iteration can be started without waiting
    ######################################################
    ./run-test-region-pair.sh \
      --stack-name "${STACK_NAME}" \
      --source-region "${SOURCE_REGION}" \
      --target-region "${TARGET_REGION}" \
      --test-uuid "${TEST_EXECUTION_UUID}" \
      --s3-bucket "${S3_BUCKET_NAME}" \
      --file-name "${FILE_NAME}" &

    ######################################################
    # For the next iteration
    ######################################################
    REGION_PAIRS=$(echo "${REGION_PAIRS}" | grep -v "${PICKED_UP}")
    sleep 5s # To let EC2 be captured the by describe-instances commands in the next iteration

  # elif [ -n "${SOURCE_INSTANCE_ID}" ] && [ -z "${TARGET_INSTANCE_ID}" ] ; then
  #   echo "${SOURCE_REGION} has EC2 running. So try again in the next iteration"
  # elif [ -z "${SOURCE_INSTANCE_ID}" ] && [ -n "${TARGET_INSTANCE_ID}" ] ; then
  #   echo "${TARGET_REGION} has EC2 running. So try again in the next iteration"
  # elif [ -n "${SOURCE_INSTANCE_ID}" ] && [ -n "${TARGET_INSTANCE_ID}" ] ; then
  #   echo "Both ${SOURCE_REGION} and ${TARGET_INSTANCE_ID} has EC2 running. So try again in the next iteration"
  # else
  #   echo "WAZZUP!??"

  fi
done
