variable "region" {
  default = "us-east-1"
}

variable "application_name" {
  type    = string
  default = "terramino"
}

variable "slack_app_token" {
  type        = string
  description = "Slack App Token"
}

