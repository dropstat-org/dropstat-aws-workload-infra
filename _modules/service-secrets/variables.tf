variable "db_users" {
  description = "Database users whose password is generated here. key -> secret name, username and a version to bump for rotation."
  type = map(object({
    secret_name = string
    username    = string
    description = optional(string, "")
    version     = optional(number, 1)
  }))
  default = {}
}

variable "db_host" {
  type    = string
  default = ""
}

variable "db_port" {
  type    = number
  default = 3306
}

variable "db_name" {
  type    = string
  default = ""
}

variable "static_secrets" {
  description = "Secrets created with REPLACE_ME placeholders and filled by hand afterwards. Terraform rewrites them only when version changes."
  type = map(object({
    secret_name = string
    keys        = list(string)
    description = optional(string, "")
    version     = optional(number, 1)
  }))
  default = {}
}

variable "password_length" {
  type    = number
  default = 32
}

variable "recovery_window_in_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
