#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

######################################
# 2. Generate input json files
######################################
# sed to remove whitespace
INSTANCE_TYPES=$(grep -v "#" < "instance-types.txt" | sed -e 's/\s//g' | grep -v "^$")

for REGION in $(jq -r 'keys | .[]' cloudformation/output.json)
do 
  AVAILABILITY_ZONE=$(jq -r ".\"${REGION}\".availability_zone" cloudformation/output.json)

  CHOSEN_INSTANCE_TYPE=""
  for INSTANCE_TYPE in $INSTANCE_TYPES
  do
    if [ "true" = "$(jq ".\"${AVAILABILITY_ZONE}\".\"${INSTANCE_TYPE}\"" aws-ec2-instance-types/output.json)" ] ; then
      CHOSEN_INSTANCE_TYPE=${INSTANCE_TYPE}
      break
    fi
  done

  if [ -z "${CHOSEN_INSTANCE_TYPE}" ] ; then
    >&2 echo "ERROR: none of instance types defined in file=${INSTANCE_PRIORITY_FILE} can be used in availability-zone=${AVAILABILITY_ZONE} of region=${REGION}"
    exit 1
  else
    echo "{ \"${REGION}\": { \"instance_type\": \"${CHOSEN_INSTANCE_TYPE}\" } }" > "intermediate/${REGION}.json"
  fi
done

######################################
# 3. Aggregate json
######################################
OUTPUT_FILE=input.json
cp "cloudformation/output.json" "${OUTPUT_FILE}"
for JSON_FILE in intermediate/*.json
do
  OUTPUT=$(jq -s '.[0] * .[1]' "${OUTPUT_FILE}" "${JSON_FILE}")
  echo "${OUTPUT}" > "${OUTPUT_FILE}"
done
