Setup Instructions

1.  Local Machine Setup

    Open a new Terminal window

    Clone the repo:

    ```python
    git clone https://github.com/l3xcaliburr/video-resizing-app.git
    ```

    Install the AWS CLI (if not already installed):

    ```python
    brew install awscli
    ```

    Configure the AWS CLI

    ```python
    aws configure
    ```

    Follow the prompts to enter:

    AWS Access Key ID
    AWS Secret Access Key
    Default region (e.g., us-east-1)
    Default output format (e.g., json)

    Set Terminal session variables

    Create the env.sh file in the root directory of the project:

    ```python
    touch env.sh
    chmod 600 env.sh
    echo "env.sh" >> .gitignore
    ```

    ```python
    chmod 600 env.sh
    ```

    ```python
    echo "env.sh" >> .gitignore
    ```

    Note: The env.sh file stores your environment variables, such as API IDs, Lambda ARNs, and bucket names. If you close your terminal session during the project, run the following command to reload the variables into your session:

    ```python
    source env.sh
    ```

    Add your AWS account ID to the variables file

    ```python
    ACCOUNT_ID=$(aws sts get-caller-identity --query "Account"  --output text)
    ```

    ```python
    echo "export ACCOUNT_ID=$ACCOUNT_ID" >> env.sh
    ```

2.  AWS S3 Buckets Configuration

    Create input/output and user interface buckets (ensure you use unique bucket names):

    ```python
    IN_BUCKET=$(aws s3 mb s3://your-bucket-name/ --output text | awk '{print $NF}')
    ```

    ```python
    OUT_BUCKET=$(aws s3 mb s3://your-output-bucket-name/ --output text | awk '{print $NF}')
    ```

    ```python
    UI_BUCKET=$(aws s3 mb s3://your-ui-bucket-name/ --output text | awk '{print $NF}')
    ```

    Set the bucket variables

    ```python
    echo -e "export IN_BUCKET=$IN_BUCKET\nexport OUT_BUCKET=$OUT_BUCKET\nexport UI_BUCKET=$UI_BUCKET" >> env.sh
    ```

    Ensure buckets are present in S3

    ```python
    aws s3 ls
    ```

    Configure public access for the buckets:

    ```python
    aws s3api put-public-access-block \
    --bucket $IN_BUCKET \
    --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
    ```

    ```python
    aws s3api put-public-access-block \
    --bucket $OUT_BUCKET \
    --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
    ```

    ```python
    aws s3api put-public-access-block \
    --bucket $UI_BUCKET \
    --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false
    ```

    Set the index and error documents for the user-interface bucket

    ```python
    aws s3 website s3://$UI_BUCKET/ \
    --index-document index.html \
    --error-document error.htm
    ```

    Set CORS configurations for input and output buckets:

    ```python
    aws s3api put-bucket-cors --bucket $IN_BUCKET --cors-configuration '{"CORSRules":[{"AllowedOrigins":["*"],"AllowedMethods":["PUT","GET","POST","HEAD"],"AllowedHeaders":["*"],"ExposeHeaders":["ETag"],"MaxAgeSeconds":3000}]}'
    ```

    ```python
    aws s3api put-bucket-cors --bucket $OUT_BUCKET --cors-configuration '{"CORSRules":[{"AllowedOrigins":["*"],"AllowedMethods":["PUT","GET","POST","HEAD"],"AllowedHeaders":["*"],"ExposeHeaders":["ETag"],"MaxAgeSeconds":3000}]}'
    ```

    Add bucket policies:

    ```python
    aws s3api put-bucket-policy --bucket $IN_BUCKET --policy '{"Version":"2012-10-17","Statement":[{"Sid":"AllowPresignedUrlPUT","Effect":"Allow","Principal":"*","Action":"s3:PutObject","Resource":["arn:aws:s3:::'"$IN_BUCKET"'/*","arn:aws:s3:::'"$IN_BUCKET"'"],"Condition":{"Bool":{"aws:SecureTransport":"true"}}}]}'
    ```

    ```python
    aws s3api put-bucket-policy --bucket $OUT_BUCKET --policy '{"Version":"2012-10-17","Statement":[{"Sid":"AllowMediaConvertAccess","Effect":"Allow","Principal":{"Service":"mediaconvert.amazonaws.com"},"Action":"s3:PutObject","Resource":"arn:aws:s3:::'"$OUT_BUCKET"'/*","Condition":{"StringEquals":{"AWS:SourceAccount":"867344447298"},"ArnLike":{"AWS:SourceArn":"arn:aws:mediaconvert:*:867344447298:*"}}},{"Sid":"AllowPreSignedURLAccess","Effect":"Allow","Principal":"*","Action":"s3:GetObject","Resource":"arn:aws:s3:::'"$OUT_BUCKET"'/*","Condition":{"StringLike":{"aws:UserAgent":"AWS-SDK-*"}}}]}'
    ```

    Copy the test-video.mp4 into the S3 input bucket:

    ```python
    aws s3 cp ./test-video.mp4 s3://$IN_BUCKET/test-video.mp4
    ```

3.  IAM Role Setup

    ```python
    cd infrastructure/
    ```

    Create a trust policy (trust-policy.json):

    ```python
    echo '{"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}, {"Effect": "Allow", "Principal": {"Service": "mediaconvert.amazonaws.com"}, "Action": "sts:AssumeRole"}, {"Effect": "Allow", "Principal": {"Service": "apigateway.amazonaws.com"}, "Action": "sts:AssumeRole"}]}' >> trust-policy.json
    ```

    Create the IAM role and attach the trust policy

    ```python
    IAM_ROLE=$(aws iam create-role --role-name VidResizer --assume-role-policy-document file://trust-policy.json --query "Role.RoleName" --output text)
    ```

    ```python
    echo "export IAM_ROLE=$IAM_ROLE" >> ../env.sh
    ```

    Build a policy.json (vid-resizer-policy.json) for the IAM role using the shell script:

    ```python
    chmod +x role-policy-build.sh \
    ./role-policy-build.sh
    ```

    Add the role policy to gitignore due to sensitive information

    ```python
    echo "template.role-policy.json" >> ../.gitignore
    ```

    Attach the role policy to the IAM role:

    ```python
    aws iam put-role-policy --role-name $IAM_ROLE --policy-name VidResizerPolicy --policy-document file://role-policy.json
    ```

4.  Lambda Function

    Create the lambda function:

    ```python
    cd ../backend
    ```

    Zip and deploy the function:

    ```python
    zip function.zip resize_video.py
    ```

    ```python
    aws lambda create-function \
    --function-name VidResizer \
    --runtime python3.11 \
    --role arn:aws:iam::$ACCOUNT_ID:role/$IAM_ROLE \
    --handler resize_video.lambda_handler \
    --zip-file fileb://function.zip
    --timeout 30
    ```

    Set Lambda environment variables:

    ```python
    aws lambda update-function-configuration \
    --function-name VidResizer \
    --environment "Variables={INPUT_BUCKET=$IN_BUCKET,MEDIACONVERT_ROLE=arn:aws:iam::$ACCOUNT_ID:role/$IAM_ROLE}"
    ```

    Set Terminal session variables for the new function:

    ```python
    LAMBDA_ARN=$(aws lambda get-function --function-name VidResizer --query 'Configuration.FunctionArn' --output text)
    echo "export LAMBDA_ARN=$LAMBDA_ARN" >> ../env.sh
    ```

    ```python
    echo "export LAMBDA_ARN=$LAMBDA_ARN" >> ../env.sh
    ```

    ```python
    LAMBDA_NAME=$(aws lambda get-function --function-name VidResizer --query 'Configuration.FunctionName' --output text)
    ```

    ```python
    echo "export LAMBDA_NAME=$LAMBDA_NAME" >> ../env.sh
    ```

5.  API Gateway

    Create a REST API Gateway and set session variables:

    ```python
    API_ID=$(aws apigateway create-rest-api \
    --name "VidResizerAPI" \
    --description "API to trigger the video resizing Lambda function" \
    --query "id" --output text)
    ```

    ```python
    echo "export API_ID=$API_ID" >> ../env.sh
    ```

    Retrieve the Root Resource ID:

    ```python
    ROOT_RESOURCE_ID=$(aws apigateway get-resources \
    --rest-api-id $API_ID \
    --query "items[?path=='/'].id" --output text)
    ```

    ```python
    echo "export ROOT_RESOURCE_ID=$ROOT_RESOURCE_ID" >> ../env.sh
    ```

    Create the /resize Resource:

    ```python
    RESIZE_RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_RESOURCE_ID \
    --path-part resize \
    --query "id" --output text)
    ```

    ```python
    echo "export RESIZE_RESOURCE_ID=$RESIZE_RESOURCE_ID" >> ../env.sh
    ```

    Create the /presigned-url Resource:

    ```python
    URL_RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_RESOURCE_ID \
    --path-part presigned-url\
    --query "id" --output text)
    ```

    ```python
    echo "export URL_RESOURCE_ID=$URL_RESOURCE_ID" >> ../env.sh
    ```

    ```python
    JOB_STATUS_RESOURCE_ID=$(aws apigateway create-resource \
    --rest-api-id $API_ID \
    --parent-id $ROOT_RESOURCE_ID \
    --path-part job-status \
    --query "id" --output text)
    ```

    ```python
    echo "export JOB_STATUS_RESOURCE_ID=$JOB_STATUS_RESOURCE_ID" >> ../env.sh
    ```

    Create a POST method for /resize:

    ```python
    aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESIZE_RESOURCE_ID \
    --http-method POST \
    --authorization-type "NONE"
    ```

    Set Up /resize POST Method Integration with Lambda Function:

    ```python
    aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESIZE_RESOURCE_ID \
    --http-method POST \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations
    ```

    Create an OPTIONS method for /resize

    ```python
    aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $RESIZE_RESOURCE_ID \
    --http-method OPTIONS \
    --authorization-type "NONE"
    ```

    Set up /resize OPTIONS Method Integration

    ```python
    aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $RESIZE_RESOURCE_ID \
    --http-method OPTIONS \
    --type MOCK \
    --request-templates '{"application/json":"{\"statusCode\": 200}"}'
    ```

    ```python
    aws apigateway put-method-response \
    --rest-api-id $API_ID \
    --resource-id $RESIZE_RESOURCE_ID \
    --http-method OPTIONS \
    --status-code 200 \
    --response-parameters "method.response.header.Access-Control-Allow-Origin=true,method.response.header.Access-Control-Allow-Methods=true,method.response.header.Access-Control-Allow-Headers=true"
    ```

    ```python
    aws apigateway put-integration-response \
    --rest-api-id $API_ID \
    --resource-id $RESIZE_RESOURCE_ID \
    --http-method OPTIONS \
    --status-code 200 \
    --response-parameters '{"method.response.header.Access-Control-Allow-Origin":"'\''*'\''","method.response.header.Access-Control-Allow-Methods":"'\''GET,POST,OPTIONS'\''","method.response.header.Access-Control-Allow-Headers":"'\''Content-Type'\''"}' \
    --response-templates '{"application/json":"{}"}'
    ```

    Create a GET method for /presigned-url

    ```python
    aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $URL_RESOURCE_ID \
    --http-method GET \
    --authorization-type "NONE"
    ```

    Create a GET method for /job-status

    ```python
    aws apigateway put-method \
    --rest-api-id $API_ID \
    --resource-id $JOB_STATUS_RESOURCE_ID \
    --http-method GET \
    --authorization-type "NONE"
    ```

    Set Up /presigned-url GET Method Integration with Lambda Function:

    ```python
    aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $URL_RESOURCE_ID \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations
    ```

    Set Up /job-status GET Method Integration with Lambda Function:

    ```python
    aws apigateway put-integration \
    --rest-api-id $API_ID \
    --resource-id $JOB_STATUS_RESOURCE_ID \
    --http-method GET \
    --type AWS_PROXY \
    --integration-http-method POST \
    --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations
    ```

    Grant API Gateway permissions:

    ```python
    aws lambda add-permission \
    --function-name $LAMBDA_NAME \
    --statement-id apigateway-invoke-permission \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn arn:aws:execute-api:us-east-1:$ACCOUNT_ID:$API_ID/*/POST/resize
    ```

    ```python
    aws lambda add-permission \
    --function-name $LAMBDA_NAME \
    --statement-id apigateway-invoke-permission-get \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn arn:aws:execute-api:us-east-1:$ACCOUNT_ID:$API_ID/*/GET/presigned-url
    ```

    ````python
    aws lambda add-permission \
    --function-name $LAMBDA_NAME \
    --statement-id apigateway-invoke-permission-job-status \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn arn:aws:execute-api:us-east-1:$ACCOUNT_ID:$API_ID/*/GET/job-status
    ```

    Deploy the API Gateway

    ```python
    aws apigateway create-deployment --rest-api-id $API_ID --stage-name production --description "Deploying API2 with CORS enabled"
    ````

    Create a payload file and test the lambda function and the api gateway

    ```python
    echo '{
        "bucket": "'$IN_BUCKET'",
        "key": "test-video.mp4",
        "output_bucket": "'$OUT_BUCKET'",
        "output_key": "resized-video.mp4"
    }' > payload.json
    ```

    Wait 1-2 minutes for the gateway to be fully deployed then run:

    ```python
    curl -X POST -H "Content-Type: application/json" -d @payload.json https://${API_ID}.execute-api.us-east-1.amazonaws.com/production/resize/
    ```

    Verify "resized-video.mp4" exists in the output bucket and then delete

    ```python
    aws s3 ls s3://$OUT_BUCKET/
    ```

    ```python
    aws s3 rm s3://$OUT_BUCKET/resized-video.mp4
    aws s3 rm s3://$IN_BUCKET/test-video.mp4
    ```

    ```python
    aws s3 rm s3://$IN_BUCKET/test-video.mp4
    ```

6.  CloudFront & UI Deployment

    CD into the frontend directory:

    ```python
    cd ../frontend
    ```

    Run script.js-build.sh to create the dynamic script.js that is unique to your specific project variables

    ```python
    chmod +x script.js-build.sh
    ```

    ```python
    ./script.js-build.sh
    ```

    ```python
    echo "script.js" >> .gitignore
    ```

    Push the local frontend files to your user-interface bucket

    ```python
    aws s3 sync ./ s3://$UI_BUCKET/ \
    --exclude "*" \
    --include "index.html" \
    --include "styles.css" \
    --include "script.js" \
    --include "background.png"
    ```

    Create an Origin Access Control for the user interface:

    ```python
    OAC_ID=$(aws cloudfront create-origin-access-control --origin-access-control-config '{"Name":"VidResizerOac","Description":"Access for CloudFront to Video Resizer UI","SigningProtocol":"sigv4","SigningBehavior":"always","OriginAccessControlOriginType":"s3"}' --query "OriginAccessControl.Id" --output text)
    ```

    ```python
    echo "export OAC_ID=$OAC_ID" >> ../env.sh
    ```

    CD into infrastructure/ and create a cloudfront distribution using the yaml file template

    ```python
    cd ../infrastructure/
    ```

    ```python
    chmod +x ./cloudfront-distribution-build.sh
    ```

    ```python
    ./cloudfront-distribution-build.sh
    ```

    Deploy stack:

    ```python
    aws cloudformation deploy \
    --template-file cloudfront-distribution.yaml \
    --stack-name FinalStack \
    --parameter-overrides UIBucket=$UI_BUCKET OACID=$OAC_ID
    ```

    Wait approximately 5-8 minutes for the stack to complete. You can check the status by running:

    ```python
    aws cloudformation describe-stacks --stack-name FinalStack
    ```

    Retrieve the CloudFront Distribution ID:

    ```python
    DISTRIBUTION_ID=$(aws cloudformation describe-stacks \
    --stack-name FinalStack \
    --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'].OutputValue" \
    --output text)
    ```

    ```python
    echo "export DISTRIBUTION_ID=$DISTRIBUTION_ID" >> ../env.sh
    ```

    Add the user-interface bucket policy:

    ```python
    aws s3api put-bucket-policy --bucket $UI_BUCKET --policy "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"cloudfront.amazonaws.com\"},\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::$UI_BUCKET/*\",\"Condition\":{\"StringEquals\":{\"AWS:SourceArn\":\"arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DISTRIBUTION_ID\"}}},{\"Sid\":\"PublicReadGetObject\",\"Effect\":\"Allow\",\"Principal\":\"*\",\"Action\":\"s3:GetObject\",\"Resource\":\"arn:aws:s3:::$UI_BUCKET/*\"}]}"
    ```

7.  Testing

    List the distributions, navigate to the domain, upload test-video.mp4 and verify resize and download link feature works as expected.

    ```python
    aws cloudfront list-distributions \
    --query "DistributionList.Items[?Id=='$DISTRIBUTION_ID']" \
    --output json
    ```
