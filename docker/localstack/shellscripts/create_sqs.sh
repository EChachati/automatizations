#!/bin/bash

awslocal sqs create-queue --queue-name default

awslocal sqs create-queue --queue-name my-queue
awslocal sqs create-queue --queue-name my-queue-dlq
awslocal sqs create-queue --queue-name my-second-queue

awslocal sqs set-queue-attributes --queue-url http://localhost:4566/000000000000/default --attributes VisibilityTimeout=1800
awslocal sqs set-queue-attributes --queue-url http://localhost:4566/000000000000/my-queue --attributes VisibilityTimeout=1800
awslocal sqs set-queue-attributes --queue-url http://localhost:4566/000000000000/my-second-queue --attributes VisibilityTimeout=460

echo "Colas creadas correctamente."