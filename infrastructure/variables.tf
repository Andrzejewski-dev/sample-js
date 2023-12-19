variable "message" {
  type    = string
  default = "Hello world!"
}

variable "aws_account_id" {
  type    = string
  default = "354629173698"
}

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "image_name" {
  type    = string
  default = "sample-js"
}

variable "image_version" {
  type    = string
  default = "latest"
}
