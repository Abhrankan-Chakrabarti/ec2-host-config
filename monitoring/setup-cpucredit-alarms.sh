#!/usr/bin/env bash
# Recreates the burst-credit alarms for the t4g.micro. Idempotent: the topic
# is reused, an existing subscription is not duplicated, and put-metric-alarm
# overwrites by name. The email is never stored in this repo.
set -euo pipefail

INSTANCE_ID=${INSTANCE_ID:-i-0da26b37e9f8a0657}
TOPIC_NAME=${TOPIC_NAME:-ec2-cpucredit-alerts}
ALERT_EMAIL=${ALERT_EMAIL:-${1:-}}

if [ -z "$ALERT_EMAIL" ]; then
  echo "usage: ALERT_EMAIL=you@example.com $0" >&2
  exit 2
fi

topic_arn=$(aws sns create-topic --name "$TOPIC_NAME" --query TopicArn --output text)

already=$(aws sns list-subscriptions-by-topic --topic-arn "$topic_arn" \
  --query "Subscriptions[?Endpoint=='$ALERT_EMAIL'] | length(@)" --output text)
if [ "$already" = "0" ]; then
  aws sns subscribe --topic-arn "$topic_arn" --protocol email \
    --notification-endpoint "$ALERT_EMAIL" --query SubscriptionArn --output text >/dev/null
  echo "subscribed $ALERT_EMAIL - confirm via the AWS email before it delivers"
else
  echo "subscription for $ALERT_EMAIL already exists"
fi

aws cloudwatch put-metric-alarm \
  --alarm-name ec2-cpucreditbalance-low \
  --alarm-description "t4g.micro CPU credit balance below 30 for 15 minutes; earns 12 credits/hour" \
  --namespace AWS/EC2 \
  --metric-name CPUCreditBalance \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Minimum \
  --period 300 \
  --evaluation-periods 3 \
  --datapoints-to-alarm 3 \
  --threshold 30 \
  --comparison-operator LessThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$topic_arn" \
  --ok-actions "$topic_arn"

aws cloudwatch put-metric-alarm \
  --alarm-name ec2-cpusurplus-charged \
  --alarm-description "Surplus CPU credits charged; unlimited mode is billing above baseline" \
  --namespace AWS/EC2 \
  --metric-name CPUSurplusCreditsCharged \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 0 \
  --comparison-operator GreaterThanThreshold \
  --treat-missing-data notBreaching \
  --alarm-actions "$topic_arn" \
  --ok-actions "$topic_arn"

echo "--- topic ---"
echo "$topic_arn"

echo "--- alarms ---"
aws cloudwatch describe-alarms \
  --alarm-names ec2-cpucreditbalance-low ec2-cpusurplus-charged \
  --query 'MetricAlarms[*].[AlarmName,StateValue,MetricName,Statistic,Period,EvaluationPeriods,DatapointsToAlarm,Threshold,ComparisonOperator,TreatMissingData]' \
  --output table
