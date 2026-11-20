variable "name" {
  type        = string
  description = "Service name. Prefixes every resource the module creates."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,24}$", var.name))
    error_message = "name must be lowercase alphanumeric with dashes, 2-25 characters."
  }
}

variable "vpc_id" {
  type        = string
  description = "VPC the blue and green target groups live in."
}

variable "listener_arn" {
  type        = string
  description = "HTTPS listener ARN the weighted rule is attached to."
}

variable "listener_rule_priority" {
  type        = number
  description = "Unused rule priority on the listener. Keep it recorded next to the service."

  validation {
    condition     = var.listener_rule_priority > 0 && var.listener_rule_priority <= 50000
    error_message = "listener_rule_priority must be between 1 and 50000."
  }
}

variable "host_header" {
  type        = string
  description = "Host header the rule matches."
}

variable "load_balancer_arn_suffix" {
  type        = string
  description = "ALB ARN suffix (module.alb.arn_suffix) used for alarm dimensions."
}

variable "port" {
  type        = number
  description = "Traffic port of the target groups."
  default     = 8080
}

variable "health_check_path" {
  type        = string
  description = "HTTP path used for target group health checks."
  default     = "/healthz"
}

variable "deregistration_delay" {
  type        = number
  description = "Seconds a detached target drains before it is closed."
  default     = 30
}

variable "green_weight" {
  type        = number
  description = "Percent of matched traffic sent to green. 0 is blue-only, 100 is full promotion."
  default     = 0

  validation {
    condition     = var.green_weight >= 0 && var.green_weight <= 100
    error_message = "green_weight must be between 0 and 100."
  }
}

variable "alarm_actions" {
  type        = list(string)
  description = "Actions fired by the promotion gate alarm."
  default     = []
}

variable "green_error_threshold" {
  type        = number
  description = "5xx count per minute on green that trips the gate alarm."
  default     = 5
}

variable "tags" {
  type        = map(string)
  description = "Extra tags merged onto every tagged resource."
  default     = {}
}
