import sys
import json
import boto3
from awsglue.context import GlueContext
from pyspark.context import SparkContext
from pyspark.sql import Row
from pyspark.sql.functions import col, lower

# Initialize Glue & Spark
args = sys.argv
sc = SparkContext()
glue = GlueContext(sc)
spark = glue.spark_session

# Get buckets from args
raw_bucket = args[args.index('--raw_bucket') + 1]
processed_bucket = args[args.index('--processed_bucket') + 1]

# Initialize S3 client
s3 = boto3.client('s3')

# List JSON files in raw bucket
response = s3.list_objects_v2(Bucket=raw_bucket, Prefix='data/')
all_rows = []

for obj in response.get('Contents', []):
    if obj['Key'].endswith('.json'):
        s3_obj = s3.get_object(Bucket=raw_bucket, Key=obj['Key'])
        content = s3_obj['Body'].read().decode('utf-8')
        try:
            data = json.loads(content)
            if isinstance(data, list):
                all_rows.extend(data)
            else:
                all_rows.append(data)
        except Exception as e:
            print(f"Skipping {obj['Key']}: {e}")

# Convert JSON list into DataFrame
if all_rows:
    # Explicitly define schema fields to flatten structure
    df = spark.createDataFrame(Row(**x) for x in all_rows)

    # Ensure columns are primitive (no nested structs)
    df_clean = df.select(
        col("user_id").cast("int"),
        lower(col("event")).alias("event"),
        col("timestamp").cast("string")
    )

    # Write clean Parquet
    df_clean.coalesce(1).write.mode("overwrite").parquet(f"s3://{processed_bucket}/parquet/")

    print("✅ ETL completed successfully and written as clean parquet.")
else:
    print("⚠️ No JSON data found in raw bucket.")
