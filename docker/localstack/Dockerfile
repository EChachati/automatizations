FROM localstack/localstack


COPY ./shellscripts/create_sqs.sh /etc/localstack/init/ready.d/create_sqs.sh
COPY ./shellscripts/sns_queue.sh /etc/localstack/init/ready.d/sns_queue.sh

RUN chmod +x /etc/localstack/init/ready.d/create_sqs.sh
RUN chmod +x /etc/localstack/init/ready.d/sns_queue.sh
