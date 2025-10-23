output "raw_bucket_name" {
  value = aws_s3_bucket.raw.bucket
}

output "processed_bucket_name" {
  value = aws_s3_bucket.processed.bucket
}

output "lambda_name" {
  value = aws_lambda_function.process_stream.function_name
}

output "kinesis_stream_name" {
  value = aws_kinesis_stream.data_stream.name
}
