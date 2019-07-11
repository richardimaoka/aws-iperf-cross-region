#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

FILENAME="region-pairs.txt"
rm "${FILENAME}" 2>/dev/null # delete if exists

# Prepare REGION_PAIRS without dupe.
# (e.g.) 'ap-northeast-1 eu-west-1' is considered same as 'eu-west-1 ap-northeast-1'
# so only the former will be retained

REGIONS=$(aws ec2 describe-regions --query "Regions[].[RegionName]" --output text)
REGIONS_INNER_LOOP=$(echo "${REGIONS}")
for REGION1 in $REGIONS
do
  # to avoid the same pair appear twice
  REGIONS_INNER_LOOP=$(echo "${REGIONS_INNER_LOOP}" | grep -v "${REGION1}")
  for REGION2 in $REGIONS_INNER_LOOP
  do
    echo "${REGION1} ${REGION2}" >> "${FILENAME}"
  done
done
