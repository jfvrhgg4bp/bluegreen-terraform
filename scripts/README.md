# Rollout guard

`canary_rollout.sh` drives a promotion through the module instead of leaving
the step sizes to whoever runs `terraform apply` by hand. It applies
`green_weight` in steps, polls the gate alarm for the soak window, and applies
`0` again the moment the alarm leaves `OK`. Rollback is a weight change, so the
fleet that already took traffic stays up while blue takes it back.

## Environment

| Variable | Required | Default | Meaning |
| --- | --- | --- | --- |
| `TF_DIR` | yes | — | Stack directory that calls this module. |
| `ALARM_NAME` | yes | — | Gate alarm, e.g. `checkout-green-5xx`. |
| `SOAK_SECONDS` | no | `900` | How long each step must hold `OK`. |
| `STEPS` | no | `10 50 100` | Weight steps, in percent. |
| `POLL_SECONDS` | no | `30` | Alarm poll interval. |

```
TF_DIR=../infra/checkout ALARM_NAME=checkout-green-5xx SOAK_SECONDS=300 \
  ./scripts/canary_rollout.sh
```

Ten percent with a five minute soak is a reasonable start. Anything under one
full evaluation window of the gate alarm (two minutes) mostly exercises the
script, not the service. `INSUFFICIENT_DATA` counts as healthy so a quiet
service does not stall the run; the 5xx alarm uses `notBreaching` for the same
reason.

## Exit codes

- `0` — green reached 100 percent of traffic.
- `1` — the alarm was already firing, or left `OK` during a step. The script has
  already applied `green_weight=0`.
