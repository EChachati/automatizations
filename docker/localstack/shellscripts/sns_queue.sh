#!/usr/bin/env bash
set -euo pipefail

# 1. Crear el topic SNS
awslocal sns create-topic --name my-topic --region eu-central-1

# 2. Crear la cola SQS
awslocal sqs create-queue --queue-name my-queue --region eu-central-1

# 3. Obtener ARNs y URL de la cola
TOPIC_ARN=$(awslocal sns list-topics \
  --query "Topics[?ends_with(TopicArn, 'my-topic')].TopicArn" \
  --output text)

QUEUE_URL=$(awslocal sqs get-queue-url \
  --queue-name my-queue \
  --query "QueueUrl" \
  --output text)

QUEUE_ARN=$(awslocal sqs get-queue-attributes \
  --queue-url "$QUEUE_URL" \
  --attribute-names QueueArn \
  --query "Attributes.QueueArn" \
  --output text)

echo "QUEUE_URL: $QUEUE_URL"
echo "QUEUE_ARN: $QUEUE_ARN"
echo "TOPIC_ARN: $TOPIC_ARN"

# 4. Suscribir la cola al topic
awslocal sns subscribe \
  --topic-arn "$TOPIC_ARN" \
  --protocol sqs \
  --notification-endpoint "$QUEUE_ARN"

# # 5. Ajustar la política de la cola para que SNS pueda enviarle mensajes
# awslocal sqs set-queue-attributes \
#   --queue-url "$QUEUE_URL" \
#   --attributes Policy={"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":"*","Action":"sqs:SendMessage","Resource":"arn:aws:sqs:us-east-1:000000000000:my-queue","Condition":{"ArnEquals":{"aws:SourceArn":"arn:aws:sns:us-east-1:000000000000:my-topic"}}}]}
