variable "name" { type = string }
variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }

variable "allowed_security_group_ids" {
  type    = list(string)
  default = []
}

variable "instance_type" {
  type    = string
  default = "mq.t3.micro"
}

variable "engine_version" {
  type    = string
  default = "5.17.6"
}

variable "publicly_accessible" {
  type    = bool
  default = false
}

variable "admin_username" {
  type    = string
  default = "dropstat"
}

variable "admin_password" {
  type      = string
  sensitive = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
