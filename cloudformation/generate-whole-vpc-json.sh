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
  exit 1
fi

######################################
# 2. Main processing
######################################
# Run in background to speed it up
for REGION in $(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text)
do
  echo "Checking the VPC in region=${REGION}"
  ./generate-regional-vpc-json.sh \
    --stack-name "${STACK_NAME}" \
    --region "${REGION}" &
done

######################################
# 3. Wait until the children complete
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
echo "Finished!!"
