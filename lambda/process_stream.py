import json
import boto3
import base64
import os
from datetime import datetime

s3 = boto3.client('s3')

def lambda_handler(event, context):
    raw_bucket = os.getenv('RAW_BUCKET')

    for record in event.get('Records', []):
        try:
            # Decode Kinesis payload
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')

            if not payload.strip():
                print("⚠️ Empty payload, skipping...")
                continue

            # Parse JSON
            data = json.loads(payload)

            # Generate file name
            timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
            key = f"data/{timestamp}_{context.aws_request_id}.json"

            # Upload to S3
            s3.put_object(
                Bucket=raw_bucket,
                Key=key,
                Body=json.dumps(data, indent=2),
                ContentType='application/json'
            )

            print(f"✅ Successfully written to S3: {key}")

        except json.JSONDecodeError as e:
            print(f"❌ Invalid JSON: {e}")
            print(f"Payload: {payload[:300]}")
        except Exception as e:
            print(f"❌ Error processing record: {e}")

    return {'statusCode': 200, 'body': 'Processed successfully'}
