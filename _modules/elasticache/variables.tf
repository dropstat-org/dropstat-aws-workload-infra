variable "name" {
  type = string
}

variable "node_type" {
  type    = string
  default = "cache.t4g.micro"
}

variable "num_cache_nodes" {
  type    = number
  default = 1
}

variable "snapshot_retention_limit" {
  type    = number
  default = 0
}

variable "tags" {
  type    = map(string)
  default = {}
}
