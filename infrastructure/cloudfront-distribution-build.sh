#!/bin/bash

# Load environment variables from env.sh
source ../env.sh

# Check for required variables
if [[ -z "$UI_BUCKET" || -z "$OAC_ID" || -z "$ACCOUNT_ID" ]]; then
    echo "Error: One or more required environment variables are not set."
    echo "Ensure UI_BUCKET, OAC_ID, and ACCOUNT_ID are defined in env.sh."
    exit 1
fi

# Replace placeholders in the template and generate the final YAML file
sed -e "s/{{UI_BUCKET}}/$UI_BUCKET/g" \
    -e "s/{{OAC_ID}}/$OAC_ID/g" \
    -e "s/{{ACCOUNT_ID}}/$ACCOUNT_ID/g" \
    template.cloudfront-distribution.yaml > cloudfront-distribution.yaml

echo "Generated cloudfront.yaml with dynamic values."