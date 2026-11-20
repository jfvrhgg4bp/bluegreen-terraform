# bluegreen-terraform

Terraform module for blue/green rollouts of a service behind an existing
Application Load Balancer.

It creates the two target groups that make the split possible, a weighted
listener rule, and the CloudWatch alarm that gates promotion. Flipping
`green_weight` from `0` to `100` moves traffic in one apply; flipping it back is
the rollback. The blue target group is never destroyed during a rollout, so a
rollback is a weight change, not a redeploy.

## Why

Instance replacement is the risky part of a deploy, not the image build. A
weighted listener rule lets you canary the new fleet, watch the error rate, and
shift traffic back without waiting for a rollback pipeline. This module owns
that split so every service does it the same way.

The module does not create an ASG, a launch template, or an ALB — it attaches to
listener and LB ARNs you already have (typically from `terraform-aws-modules/alb`).
Attach the blue and green ASGs to the exported `target_group_arns`.

## Usage

```hcl
module "checkout_rollout" {
  source  = "jfvrhgg4bp/bluegreen-terraform/aws"
  version = "0.1.0"

  name                     = "checkout"
  vpc_id                   = module.vpc.vpc_id
  listener_arn             = module.alb.https_listener_arn
  listener_rule_priority   = 120
  host_header              = "checkout.example.com"
  load_balancer_arn_suffix = module.alb.arn_suffix
  port                     = 8080
  health_check_path        = "/healthz"
  green_weight             = 0
  alarm_actions            = [aws_sns_topic.oncall.arn]
}
```

Promote in two steps so the canary gets time to fail:

```sh
terraform apply -var 'green_weight=10'   # soak 15 min, watch the alarm
terraform apply -var 'green_weight=100'
```

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | `string` | — | Service name; prefixes every resource. |
| `vpc_id` | `string` | — | VPC the target groups live in. |
| `listener_arn` | `string` | — | HTTPS listener the rule attaches to. |
| `listener_rule_priority` | `number` | — | Must be unused on the listener. |
| `host_header` | `string` | — | Host the rule matches. |
| `load_balancer_arn_suffix` | `string` | — | LB suffix for alarm dimensions. |
| `port` | `number` | `8080` | Traffic port of both target groups. |
| `health_check_path` | `string` | `/healthz` | Health check path. |
| `deregistration_delay` | `number` | `30` | Seconds to drain on detach. |
| `green_weight` | `number` | `0` | Percent of traffic sent to green. |
| `alarm_actions` | `list[str]` | `[]` | SNS/pagerduty targets for the 5xx alarm. |
| `green_error_threshold` | `number` | `5` | 5xx count per minute that trips the alarm. |

## Outputs

| Name | Description |
| --- | --- |
| `target_group_arns` | Map keyed by `blue` and `green`; feed to the ASGs. |
| `target_group_names` | Same keys, for `aws_autoscaling_group.target_group_arns`. |
| `green_alarm_arn` | The promotion gate alarm. |
| `weights` | Weights currently applied, useful in CI logs. |

## Failure modes

- **Weight apply succeeds, alarm fires.** Set `green_weight = 0` and apply; blue
  is still healthy because it never left the listener. No instance churn.
- **Green is unhealthy at 10 percent.** The alarm trips on `UnHealthyHostCount`
  and 5xx; the rollout stops at 10 percent rather than 100.
- **Listener rule priority collision.** Apply fails with `PriorityInUse`; pick
  another number from the listener's rule list.
- **Stale stickiness cookie.** Promotion is sticky for one hour, so an
  already-affected client may keep hitting green after rollback. Lower
  `stickiness.duration` in `main.tf` or send a cache-busting header while testing.
- **Green ASG scaled to zero.** Requests fall through to blue while
  `green_weight` stays high; the alarm shows it, the weights do not.

## Rollback

```sh
terraform apply -var 'green_weight=0'
```

Blue weights back up in seconds and the green fleet drains behind
`deregistration_delay`. Destroy the green ASG only after the rollback is
confirmed; destroying this module while both fleets are attached removes the
rule and both target groups at once.

## Layout

```
main.tf       target groups, weighted rule, promotion alarm
variables.tf  inputs above
outputs.tf    target group handles and alarm ARN
versions.tf   provider and Terraform constraints
```

## License

MIT, see [LICENSE](LICENSE).
