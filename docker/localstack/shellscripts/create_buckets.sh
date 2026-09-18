#!/bin/bash

# Create two S3 buckets
awslocal s3 mb s3://sample-bucket
awslocal s3 mb s3://sample-bucket-prod
