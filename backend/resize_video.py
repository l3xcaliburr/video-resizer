import boto3
import json
import os

def check_job_status(job_id):
    mediaconvert_client = boto3.client('mediaconvert', region_name='us-east-1')
    endpoints = mediaconvert_client.describe_endpoints()
    endpoint_url = endpoints['Endpoints'][0]['Url']
    mediaconvert_client = boto3.client('mediaconvert', endpoint_url=endpoint_url, region_name='us-east-1')
    
    job = mediaconvert_client.get_job(Id=job_id)
    status = job['Job']['Status']
    
    if status == 'COMPLETE':
        s3 = boto3.client('s3')
        output_key = job['Job']['Settings']['OutputGroups'][0]['OutputGroupSettings']['FileGroupSettings']['Destination'].split('/')[-1]
        if not output_key.endswith('.mp4'):
            output_key += '.mp4'
            
        presigned_url = s3.generate_presigned_url(
            'get_object',
            Params={
                'Bucket': os.environ['OUTPUT_BUCKET'],
                'Key': output_key
            },
            ExpiresIn=3600
        )
        return {'status': status, 'downloadUrl': presigned_url}
    
    return {'status': status}

def lambda_handler(event, context): 
    try:
        print("Event Received:", json.dumps(event, indent=4))

        # Handle job status check
        if event['httpMethod'] == 'GET' and event.get('queryStringParameters', {}).get('jobId'):
            job_id = event['queryStringParameters']['jobId']
            print(f"Checking status for job: {job_id}")
            result = check_job_status(job_id)
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps(result)
            }

        # Handle pre-signed URL requests
        if event['httpMethod'] == 'GET' and 'queryStringParameters' in event:
            s3 = boto3.client('s3')
            input_bucket = os.environ['INPUT_BUCKET']
            
            print("Environment variables:")
            print(f"INPUT_BUCKET: {os.environ.get('INPUT_BUCKET')}")
            
            key = event['queryStringParameters'].get('key')
            if not key:
                print("Error: Missing key parameter")
                return {
                    'statusCode': 400,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*',
                        'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
                        'Access-Control-Allow-Headers': 'Content-Type'
                    },
                    'body': json.dumps({'error': 'Missing key parameter'})
                }

            try:
                print(f"Attempting to generate pre-signed URL:")
                print(f"Bucket: {input_bucket}")
                print(f"Key: {key}")
                
                presigned_url = s3.generate_presigned_url(
                    'put_object',
                    Params={'Bucket': input_bucket, 'Key': key},
                    ExpiresIn=3600
                )
                print(f"Successfully generated pre-signed URL: {presigned_url}")
                
                return {
                    'statusCode': 200,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*',
                        'Access-Control-Allow-Methods': 'PUT, POST, GET, OPTIONS',
                        'Access-Control-Allow-Headers': 'Content-Type'
                    },
                    'body': json.dumps({'url': presigned_url})
                }
            except Exception as e:
                print(f"Error type: {type(e).__name__}")
                print(f"Error generating pre-signed URL: {str(e)}")
                print(f"Error args: {e.args}")
                
                return {
                    'statusCode': 500,
                    'headers': {
                        'Content-Type': 'application/json',
                        'Access-Control-Allow-Origin': '*',
                        'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
                        'Access-Control-Allow-Headers': 'Content-Type'
                    },
                    'body': json.dumps({'error': str(e)})
                }

        # Handle MediaConvert job submission
        if event['httpMethod'] == 'POST':
            if 'body' not in event or not event['body']:
                raise ValueError("Missing body in the event")

            body = json.loads(event['body'])
            print("Parsed request body:", json.dumps(body, indent=4))

            input_bucket = body.get('bucket')
            input_key = body.get('key')
            output_bucket = body.get('output_bucket')
            output_key = body.get('output_key')

            if not input_bucket or not input_key or not output_bucket or not output_key:
                raise ValueError("Missing required parameters in the event body")

            print(f"Input bucket: {input_bucket}, Input key: {input_key}")
            print(f"Output bucket: {output_bucket}, Output key: {output_key}")

            mediaconvert_client = boto3.client('mediaconvert', region_name='us-east-1')
            print("Initialized MediaConvert client")

            endpoints = mediaconvert_client.describe_endpoints()
            endpoint_url = endpoints['Endpoints'][0]['Url']
            print("Retrieved MediaConvert endpoint URL:", endpoint_url)
            mediaconvert_client = boto3.client('mediaconvert', endpoint_url=endpoint_url, region_name='us-east-1')

            input_file = f"s3://{input_bucket}/{input_key}"
            print("Input file:", input_file)

            if output_key.endswith('.mp4'):
                output_key = output_key[:-4]

            job_settings = {
                "Role": os.environ['MEDIACONVERT_ROLE'],
                "Settings": {
                    "Inputs": [
                        {
                            "FileInput": input_file
                        }
                    ],
                    "OutputGroups": [
                        {
                            "OutputGroupSettings": {
                                "Type": "FILE_GROUP_SETTINGS",
                                "FileGroupSettings": {
                                    "Destination": f"s3://{output_bucket}/{output_key}"
                                }
                            },
                            "Outputs": [
                                {
                                    "ContainerSettings": {
                                        "Container": "MP4"
                                    },
                                    "VideoDescription": {
                                        "Width": body.get('width', 1280),  # Use the width from the request body, default to 1280
                                        "Height": body.get('height', 720),  # Use the height from the request body, default to 720
                                        "CodecSettings": {
                                            "Codec": "H_264",
                                            "H264Settings": {
                                                "Bitrate": 5000000,
                                                "RateControlMode": "CBR",
                                                "GopSize": 60,
                                                "InterlaceMode": "PROGRESSIVE"
                                            }
                                        }
                                    }
                                }
                            ]
                        }
                    ]
                }
            }

            print("Submitting MediaConvert job with settings:", json.dumps(job_settings, indent=4))
            response = mediaconvert_client.create_job(**job_settings)
            job_id = response['Job']['Id']
            print("MediaConvert job created successfully, Job ID:", job_id)

            return {
                "statusCode": 200,
                "headers": {
                    "Content-Type": "application/json",
                    "Access-Control-Allow-Origin": "*",
                    "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
                    "Access-Control-Allow-Headers": "Content-Type"
                },
                "body": json.dumps({
                    "message": "MediaConvert job created successfully",
                    "jobId": job_id
                })
            }

    except ValueError as e:
        print("Validation Error:", str(e))
        return {
            "statusCode": 400,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type"
            },
            "body": json.dumps({"error": str(e)})
        }
    except Exception as e:
        print("Error:", str(e))
        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "application/json",
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type"
            },
            "body": json.dumps({"error": str(e)})
        }