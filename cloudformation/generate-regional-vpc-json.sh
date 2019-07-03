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
    '--region' )
      if [ -z "$2" ]; then
          echo "option --region requires an argument -- $1" 1>&2
          exit 1
      fi
      REGION="$2"
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
  >&2 echo "ERROR: Option --stack-name needs to be specified"
  ERROR=1
fi
if [ -z "${REGION}" ] ; then
  >&2 echo "ERROR: Option --region needs to be specified"
  ERROR=1
fi

if [ -n "${ERROR}" ] ; then
  exit 1
fi

######################################
# 2. Main processing
######################################

# https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/finding-an-ami.html
AMI_LINUX2=$(aws ec2 describe-images \
  --region "${REGION}" \
  --owners amazon \
  --filters 'Name=name,Values=amzn2-ami-hvm-2.0.????????-x86_64-gp2' 'Name=state,Values=available' \
  --query "reverse(sort_by(Images, &CreationDate))[0].ImageId" \
  --output text
)

OUTPUTS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" --query "Stacks[].Outputs[]" --region "${REGION}") 
SECURITY_GROUP_ID=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="SecurityGroup") | .OutputValue')
SUBNET_ID=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="Subnet") | .OutputValue')
IAM_INSTANCE_PROFILE=$(echo "${OUTPUTS}" | jq -r '.[] | select(.OutputKey=="InstanceProfile") | .OutputValue')

# Availability zone of SUBNET_ID
AVAILABILITY_ZONE=$(aws ec2 describe-subnets \
  --query "Subnets[?SubnetId=='${SUBNET_ID}'].AvailabilityZone" \
  --output text \
  --region "${REGION}"
)

echo "{"
echo "  \"${REGION}\": {"
echo "    \"image_id\": \"${AMI_LINUX2}\","
echo "    \"security_group\": \"${SECURITY_GROUP_ID}\","
echo "    \"subnet_id\": \"${SUBNET_ID}\","
echo "    \"availability_zone\": \"${AVAILABILITY_ZONE}\","
echo "    \"instance_profile\": \"${IAM_INSTANCE_PROFILE}\""
echo "  }"
echo "}"

