locals {
  slots   = toset(["blue", "green"])
  weights = { blue = 100 - var.green_weight, green = var.green_weight }

  tags = merge(var.tags, {
    "rollout.service" = var.name
    managed-by        = "bluegreen-terraform"
  })
}

resource "aws_lb_target_group" "this" {
  for_each = local.slots

  name                 = "${var.name}-${each.key}"
  vpc_id               = var.vpc_id
  port                 = var.port
  protocol             = "HTTP"
  target_type          = "instance"
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    type            = "lb_cookie"
    enabled         = true
    cookie_duration = 3600
  }

  tags = merge(local.tags, { slot = each.key })
}

resource "aws_lb_listener_rule" "split" {
  listener_arn = var.listener_arn
  priority     = var.listener_rule_priority

  action {
    type = "forward"

    forward {
      dynamic "target_group" {
        for_each = local.weights
        content {
          arn    = aws_lb_target_group.this[target_group.key].arn
          weight = target_group.value
        }
      }

      stickiness {
        enabled  = true
        duration = 3600
      }
    }
  }

  condition {
    host_header {
      values = [var.host_header]
    }
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "green_5xx" {
  alarm_name          = "${var.name}-green-5xx"
  alarm_description   = "Green slot of ${var.name} crossed ${var.green_error_threshold} 5xx/min; roll back with green_weight=0."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.green_error_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    TargetGroup  = aws_lb_target_group.this["green"].arn_suffix
    LoadBalancer = var.load_balancer_arn_suffix
  }

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "green_unhealthy" {
  alarm_name          = "${var.name}-green-unhealthy"
  alarm_description   = "Green slot of ${var.name} has no healthy targets while receiving weight."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions

  dimensions = {
    TargetGroup  = aws_lb_target_group.this["green"].arn_suffix
    LoadBalancer = var.load_balancer_arn_suffix
  }

  tags = local.tags
}
