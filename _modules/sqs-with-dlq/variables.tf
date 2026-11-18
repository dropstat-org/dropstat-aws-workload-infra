variable "name" {
  description = "Queue name. The dead letter queue is created as <name>-dlq."
  type        = string
}

variable "message_retention_seconds" {
  type    = number
  default = 345600
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 300
}

variable "receive_wait_time_seconds" {
  type    = number
  default = 20
}

variable "max_receive_count" {
  description = "Receives before a message moves to the dead letter queue."
  type        = number
  default     = 5
}

variable "dlq_message_retention_seconds" {
  type    = number
  default = 1209600
}

variable "oldest_message_age_threshold_seconds" {
  description = "Alarm when the oldest message in the main queue is older than this."
  type        = number
  default     = 900
}

variable "slack_team_id" {
  description = "Slack workspace id authorized in AWS Chatbot for this account. Null skips the Chatbot channel."
  type        = string
  default     = null
}

variable "slack_channel_id" {
  description = "Slack channel id that receives the alarms. Null skips the Chatbot channel."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
