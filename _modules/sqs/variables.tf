variable "queue_names"                { type = list(string) }
variable "message_retention_seconds"  { type = number; default = 345600 }  # 4 days
variable "visibility_timeout_seconds" { type = number; default = 30 }
variable "tags"                       { type = map(string); default = {} }
