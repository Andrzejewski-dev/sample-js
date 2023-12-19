variable "image" {
  type = string
  default = "354629173698.dkr.ecr.eu-central-1.amazonaws.com/sample-js:latest"
}

variable "message" {
  type = string
  default = "Hello world!"
}

variable "execution_role_arn" {
  type = string
  default = "arn:aws:iam::354629173698:role/ecsTaskExecutionRole"
}

variable "bucket_name" {
  type = string
  default = "andrzejewski-dev-sample-js"
}
