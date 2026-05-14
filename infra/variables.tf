variable "project" {
  description = "프로젝트 이름. 리소스 name prefix로 사용됩니다."
  type        = string
  default     = "chatda"
}

variable "environment" {
  description = "배포 환경 이름"
  type        = string
  default     = "mvp"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-2"
}

variable "azs" {
  description = "사용할 Availability Zone 목록. RDS subnet group 때문에 2개 이상 권장."
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2c"]
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "container_port" {
  description = "FastAPI container port"
  type        = number
  default     = 8000
}

variable "app_image" {
  description = "ECS에서 실행할 FastAPI Docker image. 초기 apply 전에는 ECR URL 또는 임시 public image를 넣으세요."
  type        = string
  default     = "public.ecr.aws/docker/library/python:3.12-slim"
}

variable "desired_count" {
  description = "MVP 기본 task 수"
  type        = number
  default     = 1
}

variable "db_name" {
  type    = string
  default = "chatda"
}

variable "db_username" {
  type    = string
  default = "chatda_admin"
}

variable "db_password" {
  description = "RDS master password. 실제 운영에서는 Secrets Manager/SSM로 관리하세요."
  type        = string
  sensitive   = true
}

variable "github_org" {
  description = "GitHub organization 또는 username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "github_branch" {
  description = "OIDC assume role을 허용할 branch"
  type        = string
  default     = "main"
}

variable "alarm_email" {
  description = "CloudWatch/SNS 알림 수신 이메일. 비워두면 email subscription은 생성하지 않습니다."
  type        = string
  default     = ""
}

variable "fcm_server_key_secret_arn" {
  description = "Google FCM server key를 저장한 Secrets Manager secret ARN. Lambda에서 사용하려면 값을 넣으세요."
  type        = string
  default     = ""
}
