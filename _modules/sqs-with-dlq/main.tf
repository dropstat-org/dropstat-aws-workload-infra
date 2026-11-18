locals {
  chatbot_enabled = var.slack_team_id != null && var.slack_channel_id != null
}

module "queue" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "~> 4.0"

  name                       = var.name
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  sqs_managed_sse_enabled    = true

  create_dlq                    = true
  dlq_name                      = "${var.name}-dlq"
  dlq_message_retention_seconds = var.dlq_message_retention_seconds
  dlq_sqs_managed_sse_enabled   = true
  redrive_policy = {
    maxReceiveCount = var.max_receive_count
  }

  tags = var.tags
}

resource "aws_sns_topic" "alarms" {
  name = "${var.name}-alarms"
  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name}-dlq-not-empty"
  alarm_description   = "Messages in ${var.name}-dlq. Inspect and replay by hand."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = module.queue.dead_letter_queue_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "oldest_message_age" {
  alarm_name          = "${var.name}-oldest-message-age"
  alarm_description   = "Oldest message in ${var.name} is older than ${var.oldest_message_age_threshold_seconds} s. The worker is not consuming."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = var.oldest_message_age_threshold_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = module.queue.queue_name
  }

  alarm_actions = [aws_sns_topic.alarms.arn]
  ok_actions    = [aws_sns_topic.alarms.arn]
  tags          = var.tags
}

data "aws_iam_policy_document" "chatbot_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["chatbot.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "chatbot" {
  count              = local.chatbot_enabled ? 1 : 0
  name_prefix        = "${var.name}-chatbot-"
  assume_role_policy = data.aws_iam_policy_document.chatbot_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "chatbot_read" {
  count      = local.chatbot_enabled ? 1 : 0
  role       = aws_iam_role.chatbot[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"
}

resource "aws_chatbot_slack_channel_configuration" "alarms" {
  count                 = local.chatbot_enabled ? 1 : 0
  configuration_name    = "${var.name}-alarms"
  iam_role_arn          = aws_iam_role.chatbot[0].arn
  slack_team_id         = var.slack_team_id
  slack_channel_id      = var.slack_channel_id
  sns_topic_arns        = [aws_sns_topic.alarms.arn]
  guardrail_policy_arns = ["arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"]
  logging_level         = "ERROR"
  tags                  = var.tags
}
