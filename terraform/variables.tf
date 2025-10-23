variable "region" {
  description = "AWS region"
  default     = "ap-south-1"
}

variable "bucket_raw" {
  description = "S3 bucket for raw ingestion"
  default     = "my-datalake-raw"
}

variable "bucket_processed" {
  description = "S3 bucket for processed data"
  default     = "my-datalake-processed"
}

variable "kinesis_shard_count" {
  description = "Number of shards for Kinesis stream"
  default     = 1
}

variable "lambda_memory" {
  description = "Memory (MB) for Lambda function"
  default     = 128
}

variable "glue_worker_type" {
  description = "Glue worker type"
  default     = "G.1X"
}

variable "glue_number_of_workers" {
  description = "Glue number of workers"
  default     = 2
}
