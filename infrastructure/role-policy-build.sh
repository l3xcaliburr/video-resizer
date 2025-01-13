#!/bin/bash

# Load environment variables
source ../env.sh

# Check required variables
if [[ -z "$IN_BUCKET" || -z "$OUT_BUCKET" || -z "$ACCOUNT_ID" || -z "$IAM_ROLE" ]]; then
    echo "Error: One or more required environment variables are not set."
    echo "Ensure IN_BUCKET, OUT_BUCKET, ACCOUNT_ID, and IAM_ROLE are defined in env.sh."
    exit 1
fi

# Replace placeholders in template and generate policy file
sed -e "s/{{IN_BUCKET}}/$IN_BUCKET/g" \
    -e "s/{{OUT_BUCKET}}/$OUT_BUCKET/g" \
    -e "s/{{ACCOUNT_ID}}/$ACCOUNT_ID/g" \
    -e "s/{{IAM_ROLE}}/$IAM_ROLE/g" \
    template.role-policy.json > role-policy.json

echo "Generated video-resizer-policy.json with dynamic values."