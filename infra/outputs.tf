output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.app.domain_name
}

output "presigned_url_api_endpoint" {
  value = "${aws_apigatewayv2_api.presigned.api_endpoint}/presigned-url"
}

output "s3_images_bucket" {
  value = aws_s3_bucket.images.bucket
}

output "rds_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

output "sns_push_alerts_topic_arn" {
  value = aws_sns_topic.push_alerts.arn
}
