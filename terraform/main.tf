terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}

##########################
# S3 BUCKETS (RAW + PROCESSED)
##########################
# These act as data lake layers — raw = unprocessed input, processed = cleaned ETL output

resource "aws_s3_bucket" "raw" {
  bucket_prefix = "${var.bucket_raw}-"
  force_destroy = true
  tags = {
    Name = "data-pipeline-raw"
  }
}

resource "aws_s3_bucket" "processed" {
  bucket_prefix = "${var.bucket_processed}-"
  force_destroy = true
  tags = {
    Name = "data-pipeline-processed"
  }
}

# Enable encryption (AES256) for compliance and data security
resource "aws_s3_bucket_server_side_encryption_configuration" "raw_enc" {
  bucket = aws_s3_bucket.raw.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "processed_enc" {
  bucket = aws_s3_bucket.processed.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

##########################
# KINESIS DATA STREAM (Real-time ingestion)
##########################

resource "aws_kinesis_stream" "data_stream" {
  name        = "log-stream"
  shard_count = var.kinesis_shard_count

  stream_mode_details {
    stream_mode = "PROVISIONED"
  }

  tags = {
    Environment = "dev"
  }
}

##########################
# IAM ROLES
##########################

# Lambda Execution Role — grants access to CloudWatch Logs, S3, and Kinesis
resource "aws_iam_role" "lambda_role" {
  name = "lambda-data-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_s3" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "lambda_kinesis" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonKinesisFullAccess"
}

# Glue Role — for reading/writing S3 and logging
resource "aws_iam_role" "glue_role" {
  name = "glue-data-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "glue.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_s3" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "glue_logs" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

##########################
# LAMBDA FUNCTION
##########################
# Lambda processes streaming data from Kinesis and stores raw events in S3

resource "aws_lambda_function" "process_stream" {
  function_name = "process-kinesis-stream"
  role          = aws_iam_role.lambda_role.arn
  handler       = "process_stream.lambda_handler"
  runtime       = "python3.9"
  timeout       = 60
  memory_size   = var.lambda_memory

  filename         = "${path.module}/../lambda/process_stream.zip"
  source_code_hash = filebase64sha256("${path.module}/../lambda/process_stream.zip")

  environment {
    variables = {
      RAW_BUCKET = aws_s3_bucket.raw.bucket
    }
  }
}

# Connect Lambda to Kinesis for event-driven data ingestion
resource "aws_lambda_event_source_mapping" "kinesis_trigger" {
  event_source_arn  = aws_kinesis_stream.data_stream.arn
  function_name     = aws_lambda_function.process_stream.arn
  starting_position = "LATEST"
  batch_size        = 100
  enabled           = true
}

##########################
# GLUE ETL JOB (Batch Processing)
##########################
# Transforms raw S3 data → clean/Parquet format → writes to processed S3

resource "aws_glue_job" "etl" {
  name     = "etl_raw_to_processed"
  role_arn = aws_iam_role.glue_role.arn

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.raw.bucket}/scripts/etl_job.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"      = "python"
    "--raw_bucket"        = aws_s3_bucket.raw.bucket
    "--processed_bucket"  = aws_s3_bucket.processed.bucket
  }

  glue_version        = "4.0"
  worker_type         = var.glue_worker_type
  number_of_workers   = var.glue_number_of_workers
  max_retries         = 0
}

##########################
# GLUE CATALOG + ATHENA (Analytics Layer)
##########################
# Glue Catalog = table metadata for Athena queries
# Athena queries processed S3 data using SQL

resource "aws_glue_catalog_database" "analytics_db" {
  name = "analytics_db"
}

resource "aws_glue_catalog_table" "processed_table" {
  name          = "processed_data"
  database_name = aws_glue_catalog_database.analytics_db.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "classification" = "parquet"
    "compressionType" = "none"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.processed.bucket}/parquet/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "user_id"
      type = "int"
    }

    columns {
      name = "event"
      type = "string"
    }

    columns {
      name = "timestamp"
      type = "string"
    }
  }
}