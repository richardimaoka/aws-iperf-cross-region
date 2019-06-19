#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

#######################################################
# Step 1: Parse options and error check
#######################################################
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
    -*)
      echo "illegal option -- $1" 1>&2
      exit 1
      ;;
  esac
done

if [ -z "${STACK_NAME}" ] ; then
  >&2 echo "ERROR: Option --stack-name needs to be specified"
  exit 1
fi

FILE_NAME=$(tempfile)

# Start of JSON
echo "{"

LAST_REGION=$(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text | tail -1)
for REGION in $(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text)
do
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

  echo "\"${REGION}\": {"
  echo "  \"image_id\": \"${AMI_LINUX2}\","
  echo "  \"security_group\": \"${SECURITY_GROUP_ID}\","
  echo "  \"instance_profile\": \"${IAM_INSTANCE_PROFILE}\","
  echo "  \"subnet_id\": \"${SUBNET_ID}\""
  if [ "$REGION" = "${LAST_REGION}" ]; then 
    echo "}"
  else
    echo "},"
  fi
done

# End of JSON
echo "}"

# jq -s '.[0] * .[1]' "${FILE_NAME}" instance-types.json
# rm "${FILE_NAME}"
