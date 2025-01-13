#!/bin/bash

# Load environment variables from env.sh in the root directory
source ../env.sh

# Check if required variables are set
if [[ -z "$API_ID" || -z "$IN_BUCKET" || -z "$OUT_BUCKET" ]]; then
  echo "Error: One or more required environment variables are not set."
  echo "Ensure that API_ID, IN_BUCKET, and OUT_BUCKET are defined in env.sh."
  exit 1
fi

# Replace placeholders in script.template.js with environment variable values
sed -e "s/{{API_ID}}/$API_ID/g" \
    -e "s/{{IN_BUCKET}}/$IN_BUCKET/g" \
    -e "s/{{OUT_BUCKET}}/$OUT_BUCKET/g" \
    script.template.js > script.js

echo "Generated script.js with dynamic values."