output "target_group_arns" {
  description = "Target groups keyed by slot. Attach the matching ASG to each."
  value       = { for slot, tg in aws_lb_target_group.this : slot => tg.arn }
}

output "target_group_names" {
  description = "Target group names keyed by slot, for autoscaling_group.target_group_arns."
  value       = { for slot, tg in aws_lb_target_group.this : slot => tg.name }
}

output "green_alarm_arns" {
  description = "Promotion gate alarms on the green slot."
  value = [
    aws_cloudwatch_metric_alarm.green_5xx.arn,
    aws_cloudwatch_metric_alarm.green_unhealthy.arn,
  ]
}

output "weights" {
  description = "Weights currently applied on the listener rule, handy for CI logs."
  value       = local.weights
}
