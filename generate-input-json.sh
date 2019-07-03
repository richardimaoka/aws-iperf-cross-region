#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

######################################
# 1.1 Parse options
######################################
for OPT in "$@"
do
  case "$OPT" in
    '--instance-priority-file' )
      if [ -z "$2" ]; then
          echo "option --instance-priority-file requires an argument -- $1" 1>&2
          exit 1
      fi
      INSTANCE_PRIORITY_FILE="$2"
      shift 2
      ;;
    -*)
      echo "illegal option $1" 1>&2
      exit 1
      ;;
  esac
done

######################################
# 1.2 Validate options
######################################
if [ -z "${INSTANCE_PRIORITY_FILE}" ] ; then
  >&2 echo "ERROR: option --instance-priority-file needs to be passed"
  exit 1
fi

######################################
# 2. Generate input json files
######################################
# sed to remove whitespace
INSTANCE_TYPES=$(grep -v "#" < "${INSTANCE_PRIORITY_FILE}" | sed -e 's/\s//g')

for REGION in $(jq 'keys | .[]' cloudformation/output.json)
do  AVAILABILITY_ZONE=$(jq -r ".${REGION}.availability_zone" cloudformation/output.json)

  for INSTANCE_TYPE in $INSTANCE_TYPES
  do
    CHOSEN_INSTANCE_TYPE=""
    # jq "[\"key.with.dot\"][\"another.key.with.dot\"]" should be used for keys with dot  
    if [ -n "${INSTANCE_TYPE}" ] && \
       [ "true" = "$(jq ".[\"${AVAILABILITY_ZONE}\"][\"${INSTANCE_TYPE}\"]" aws-ec2-instance-types/output.json)" ] ; then
      CHOSEN_INSTANCE_TYPE=${INSTANCE_TYPE}
      break
    fi
  done

  if [ -z "${CHOSEN_INSTANCE_TYPE}" ] ; then
    >&2 echo "ERROR: none of instance types defined in file=${INSTANCE_PRIORITY_FILE} can be used in availability-zone=${AVAILABILITY_ZONE} of region=${REGION}"
    exit 1
  else
    echo "${REGION} ${AVAILABILITY_ZONE} ${CHOSEN_INSTANCE_TYPE}"
  fi
done

# TODO: generate json which adds instance_type to cloudformatoin/output.json and generate a new file
# TODO: generate json which adds instance_type to cloudformatoin/output.json and generate a new file
# TODO: generate json which adds instance_type to cloudformatoin/output.json and generate a new file
# TODO: generate json which adds instance_type to cloudformatoin/output.json and generate a new file
# TODO: generate json which adds instance_type to cloudformatoin/output.json and generate a new file
# TODO: generate json which adds instance_type to cloudformatoin/output.json and generate a new file


