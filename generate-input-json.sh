#!/bin/sh

# cd to the current directory as it runs other shell scripts
cd "$(dirname "$0")" || exit

######################################
# 1.1 Parse options
######################################
for OPT in "$@"
do
  case "$OPT" in
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

######################################
# 1.2 Validate options
######################################
if [ -z "${FILE_NAME}" ] ; then
  >&2 echo "ERROR: option -f or --file-name needs to be passed"
  ERROR="1"
elif ! INPUT_JSON=$(jq -r "." < "${FILE_NAME}"); then
  >&2 echo "ERROR: Failed to read input JSON from ${FILE_NAME}"
  ERROR="1"
fi

if [ -n "${ERROR}" ] ; then
  exit 1
fi

######################################
# 2. Generate input json files
######################################

# Create if not exist
mkdir -p input-files

for INSTANCE_TYPE_FILE in $(ls instance-types/)
do
  jq -s '.[0] * .[1]' "${FILE_NAME}" "instance-types/${INSTANCE_TYPE_FILE}" > "input-files/${INSTANCE_TYPE_FILE}"
done

