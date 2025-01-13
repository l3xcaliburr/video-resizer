#!/bin/bash

# Exit on error
set -e

echo "Starting Video Resizer App Setup..."

# 1. Local Machine Setup
echo "1. Setting up local environment..."

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "Git not found. Please install git first."
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI not found. Installing..."
    brew install awscli
fi

# Clone the repository
git clone https://github.com/l3xcaliburr/video-resizing-app.git
cd video-resizing-app

# Create and configure env.sh
touch env.sh
chmod 600 env.sh
echo "env.sh" >> .gitignore

# Get AWS Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
echo "export ACCOUNT_ID=$ACCOUNT_ID" >> env.sh

# 2. S3 Buckets Setup
echo "2. Setting up S3 buckets..."

# Generate unique bucket names using timestamp
TIMESTAMP=$(date +%Y%m%d%H%M%S)
IN_BUCKET="video-input-${TIMESTAMP}"
OUT_BUCKET="video-output-${TIMESTAMP}"
UI_BUCKET="video-ui-${TIMESTAMP}"

# Create buckets
aws s3 mb "s3://${IN_BUCKET}"
aws s3 mb "s3://${OUT_BUCKET}"
aws s3 mb "s3://${UI_BUCKET}"

# Set bucket variables
echo -e "export IN_BUCKET=$IN_BUCKET\nexport OUT_BUCKET=$OUT_BUCKET\nexport UI_BUCKET=$UI_BUCKET" >> env.sh

# Configure public access for buckets
for BUCKET in $IN_BUCKET $OUT_BUCKET $UI_BUCKET; do
    aws s3api put-public-access-block \
        --bucket $BUCKET \
        --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
done

# Configure UI bucket for static website hosting
aws s3 website "s3://${UI_BUCKET}/" --index-document index.html --error-document error.htm

# Set CORS configurations
CORS_CONFIG='{"CORSRules":[{"AllowedOrigins":["*"],"AllowedMethods":["PUT","GET","POST","HEAD"],"AllowedHeaders":["*"],"ExposeHeaders":["ETag"],"MaxAgeSeconds":3000}]}'
aws s3api put-bucket-cors --bucket $IN_BUCKET --cors-configuration "$CORS_CONFIG"
aws s3api put-bucket-cors --bucket $OUT_BUCKET --cors-configuration "$CORS_CONFIG"

# Add bucket policies
aws s3api put-bucket-policy --bucket $IN_BUCKET --policy '{
    "Version": "2012-10-17",
    "Statement": [{
        "Sid": "AllowPresignedUrlPUT",
        "Effect": "Allow",
        "Principal": "*",
        "Action": "s3:PutObject",
        "Resource": ["arn:aws:s3:::'$IN_BUCKET'/*","arn:aws:s3:::'$IN_BUCKET'"],
        "Condition": {"Bool": {"aws:SecureTransport": "true"}}
    }]
}'

aws s3api put-bucket-policy --bucket $OUT_BUCKET --policy '{
    "Version": "2012-10-17",
    "Statement": [{
        "Sid": "AllowMediaConvertAccess",
        "Effect": "Allow",
        "Principal": {"Service": "mediaconvert.amazonaws.com"},
        "Action": "s3:PutObject",
        "Resource": "arn:aws:s3:::'$OUT_BUCKET'/*",
        "Condition": {
            "StringEquals": {"AWS:SourceAccount": "'$ACCOUNT_ID'"},
            "ArnLike": {"AWS:SourceArn": "arn:aws:mediaconvert:*:'$ACCOUNT_ID':*"}
        }
    }, {
        "Sid": "AllowPreSignedURLAccess",
        "Effect": "Allow",
        "Principal": "*",
        "Action": "s3:GetObject",
        "Resource": "arn:aws:s3:::'$OUT_BUCKET'/*",
        "Condition": {"StringLike": {"aws:UserAgent": "AWS-SDK-*"}}
    }]
}'

# 3. IAM Role Setup
echo "3. Setting up IAM role..."

cd infrastructure/

# Create trust policy
echo '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {"Service": "lambda.amazonaws.com"},
            "Action": "sts:AssumeRole"
        },
        {
            "Effect": "Allow",
            "Principal": {"Service": "mediaconvert.amazonaws.com"},
            "Action": "sts:AssumeRole"
        },
        {
            "Effect": "Allow",
            "Principal": {"Service": "apigateway.amazonaws.com"},
            "Action": "sts:AssumeRole"
        }
    ]
}' > trust-policy.json

# Create IAM role
IAM_ROLE=$(aws iam create-role --role-name VidResizer --assume-role-policy-document file://trust-policy.json --query "Role.RoleName" --output text)
echo "export IAM_ROLE=$IAM_ROLE" >> ../env.sh

# Build and attach role policy
chmod +x role-policy-build.sh
./role-policy-build.sh
echo "template.role-policy.json" >> ../.gitignore
aws iam put-role-policy --role-name $IAM_ROLE --policy-name VidResizerPolicy --policy-document file://role-policy.json

# 4. Lambda Function Setup
echo "4. Setting up Lambda function..."

cd ../backend

# Create and deploy Lambda function
zip function.zip resize_video.py
aws lambda create-function \
    --function-name VidResizer \
    --runtime python3.11 \
    --role "arn:aws:iam::${ACCOUNT_ID}:role/${IAM_ROLE}" \
    --handler resize_video.lambda_handler \
    --zip-file fileb://function.zip \
    --timeout 30

# Set Lambda environment variables
aws lambda update-function-configuration \
    --function-name VidResizer \
    --environment "Variables={INPUT_BUCKET=${IN_BUCKET},MEDIACONVERT_ROLE=arn:aws:iam::${ACCOUNT_ID}:role/${IAM_ROLE}}"

# Set Lambda variables
LAMBDA_ARN=$(aws lambda get-function --function-name VidResizer --query 'Configuration.FunctionArn' --output text)
LAMBDA_NAME=$(aws lambda get-function --function-name VidResizer --query 'Configuration.FunctionName' --output text)
echo -e "export LAMBDA_ARN=$LAMBDA_ARN\nexport LAMBDA_NAME=$LAMBDA_NAME" >> ../env.sh

# 5. API Gateway Setup
echo "5. Setting up API Gateway..."

# Create REST API
API_ID=$(aws apigateway create-rest-api \
    --name "VidResizerAPI" \
    --description "API to trigger the video resizing Lambda function" \
    --query "id" --output text)
echo "export API_ID=$API_ID" >> ../env.sh

# Get root resource ID
ROOT_RESOURCE_ID=$(aws apigateway get-resources \
    --rest-api-id $API_ID \
    --query "items[?path=='/'].id" --output text)
echo "export ROOT_RESOURCE_ID=$ROOT_RESOURCE_ID" >> ../env.sh

# Create resources
RESIZE_RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_RESOURCE_ID \
    --path-part resize \
    --query "id" --output text)

URL_RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_RESOURCE_ID \
    --path-part presigned-url \
    --query "id" --output text)

JOB_STATUS_RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_RESOURCE_ID \
    --path-part job-status \
    --query "id" --output text)

echo -e "export RESIZE_RESOURCE_ID=$RESIZE_RESOURCE_ID\nexport URL_RESOURCE_ID=$URL_RESOURCE_ID\nexport JOB_STATUS_RESOURCE_ID=$JOB_STATUS_RESOURCE_ID" >> ../env.sh

# Set up methods and integrations
# POST /resize
aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESIZE_RESOURCE_ID \
    --http-method POST \
    --authorization-type "NONE"

aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESIZE_RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"

# OPTIONS /resize
aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESIZE_RESOURCE_ID \
    --http-method OPTIONS \
    --authorization-type "NONE"

aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESIZE_RESOURCE_ID \
    --http-method OPTIONS \
    --type MOCK \
    --request-templates '{"application/json":"{\"statusCode\": 200}"}'

aws apigateway put-method-response \
    --rest-api-id $API_ID \
    --resource-id $RESIZE_RESOURCE_ID \
    --http-method OPTIONS \
    --status-code 200 \
    --response-parameters "method.response.header.Access-Control-Allow-Origin=true,method.response.header.Access-Control-Allow-Methods=true,method.response.header.Access-Control-Allow-Headers=true"

aws apigateway put-integration-response \
    --rest-api-id $API_ID \
    --resource-id $RESIZE_RESOURCE_ID \
    --http-method OPTIONS \
    --status-code 200 \
    --response-parameters '{"method.response.header.Access-Control-Allow-Origin":"'\''*'\''","method.response.header.Access-Control-Allow-Methods":"'\''GET,POST,OPTIONS'\''","method.response.header.Access-Control-Allow-Headers":"'\''Content-Type'\''"}'

# GET /presigned-url and /job-status
for RESOURCE_ID in $URL_RESOURCE_ID $JOB_STATUS_RESOURCE_ID; do
    aws apigateway put-method \
        --rest-api-id $API_ID \
        --resource-id $RESOURCE_ID \
        --http-method GET \
        --authorization-type "NONE"

    aws apigateway put-integration \
        --rest-api-id $API_ID \
        --resource-id $RESOURCE_ID \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"
done

# Grant permissions to API Gateway
aws lambda add-permission \
    --function-name $LAMBDA_NAME \
    --statement-id apigateway-invoke-permission \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:us-east-1:${ACCOUNT_ID}:${API_ID}/*/POST/resize"

aws lambda add-permission \
    --function-name $LAMBDA_NAME \
    --statement-id apigateway-invoke-permission-get \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:us-east-1:${ACCOUNT_ID}:${API_ID}/*/GET/presigned-url"

aws lambda add-permission \
    --function-name $LAMBDA_NAME \
    --statement-id apigateway-invoke-permission-job-status \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:us-east-1:${ACCOUNT_ID}:${API_ID}/*/GET/job-status"

# Deploy API
aws apigateway create-deployment \
    --rest-api-id $API_ID \
    --stage-name production \
    --description "Deploying API with CORS enabled"

# 6. CloudFront & UI Deployment
echo "6. Setting up CloudFront and deploying UI..."

cd ../frontend

# Build script.js
chmod +x script.js-build.sh
./script.js-build.sh
echo "script.js" >> .gitignore

# Deploy frontend files
aws s3 sync ./ "s3://${UI_BUCKET}/" \
    --exclude "*" \
    --include "index.html" \
    --include "styles.css" \
    --include "script.js" \
    --include "background.png"

# Create Origin Access Control
OAC_ID=$(aws cloudfront create-origin-access-control \
    --origin-access-control-config '{
        "Name": "VidResizerOac",
        "Description": "Access for CloudFront to Video Resizer UI",
        "SigningProtocol": "sigv4",
        "SigningBehavior": "always",
        "OriginAccessControlOriginType": "s3"
    }' \
    --query "OriginAccessControl.Id" --output text)
echo "export OAC_ID=$OAC_ID" >> ../env.sh

# Build and deploy CloudFront distribution
cd ../infrastructure/
chmod +x ./cloudfront-distribution-build.sh
./cloudfront-distribution-build.sh

aws cloudformation deploy \
    --template-file cloudfront-distribution.yaml \
    --stack-name FinalStack \
    --parameter-overrides UIBucket=$UI_BUCKET OACID=$OAC_ID

# Wait for stack completion
echo "Waiting for CloudFront distribution to be deployed (this may take 5-8 minutes)..."
aws cloudformation wait stack-create-complete --stack-name FinalStack

# Get distribution ID
DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
    --stack-name FinalStack \
    --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
    --output text)
echo "export DISTRIBUTION_ID=$DISTRIBUTION_ID" >> ../env.sh

# Set UI bucket policy
aws s3api put-bucket-policy --bucket $UI_BUCKET --policy "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
        {
            \"Effect\": \"Allow\",
            \"Principal\": {\"Service\": \"cloudfront.amazonaws.com\"},
            \"Action\": \"s3:GetObject\",
            \"Resource\": \"arn:aws:s3:::$UI_BUCKET/*\",
            \"Condition\": {
                \"StringEquals\": {
                    \"AWS:SourceArn\": \"arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DISTRIBUTION_ID\"
                }
            }
        },
        {
            \"Sid\": \"PublicReadGetObject\",
            \"Effect\": \"Allow\",
            \"Principal\": \"*\",
            \"Action\": \"s3:GetObject\",
            \"Resource\": \"arn:aws:s3:::$UI_BUCKET/*\"
        }
    ]
}"

# 7. Final Testing
echo "7. Running final tests..."

# Create test payload
echo '{
    "bucket": "'$IN_BUCKET'",
    "key": "test-video.mp4",
    "output_bucket": "'$OUT_BUCKET'",
    "output_key": "resized-video.mp4"
}' > test-payload.json

# Test API endpoint
echo "Testing API endpoint..."
sleep 120  # Wait for API Gateway deployment to complete
CURL_RESPONSE=$(curl -X POST -H "Content-Type: application/json" -d @test-payload.json https://${API_ID}.execute-api.us-east-1.amazonaws.com/production/resize/)
echo "API Response: $CURL_RESPONSE"

# Get CloudFront distribution details
DISTRIBUTION_DOMAIN=$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Id=='$DISTRIBUTION_ID'].DomainName" \
    --output text)

echo "Setup completed successfully!"
echo "============================================"
echo "Important Information:"
echo "--------------------------------------------"
echo "CloudFront Domain: https://$DISTRIBUTION_DOMAIN"
echo "API Gateway Endpoint: https://${API_ID}.execute-api.us-east-1.amazonaws.com/production"
echo "Input Bucket: $IN_BUCKET"
echo "Output Bucket: $OUT_BUCKET"
echo "UI Bucket: $UI_BUCKET"
echo "============================================"
echo "Note: Please wait 5-10 minutes for the CloudFront distribution to fully deploy before accessing the application."
echo "You can now access your application at: https://$DISTRIBUTION_DOMAIN"

# Source the environment variables
source ../env.sh