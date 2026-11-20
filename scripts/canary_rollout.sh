#!/usr/bin/env bash
# Step a bluegreen-terraform stack toward green in canary increments and flip
# the weight back to 0 as soon as the promotion gate alarm leaves OK.
#
# Requires: terraform in PATH, aws CLI with read access to CloudWatch alarms.
# Writes only the green_weight variable; a rollback is a weight change, not a
# redeploy, so the blast radius stays at the traffic share of the failed step.
set -euo pipefail

: "${TF_DIR:?path to the stack that calls the bluegreen-terraform module}"
: "${ALARM_NAME:?promotion gate alarm name, e.g. checkout-green-5xx}"
: "${SOAK_SECONDS:=900}"
: "${STEPS:=10 50 100}"
: "${POLL_SECONDS:=30}"

tf() { terraform -chdir="$TF_DIR" "$@"; }

alarm_state() {
  aws cloudwatch describe-alarms \
    --alarm-names "$ALARM_NAME" \
    --query 'MetricAlarms[0].StateValue' \
    --output text
}

set_weight() {
  tf apply -auto-approve -input=false -var "green_weight=$1"
}

rollback() {
  echo "guard: gate alarm is not OK at ${1}% green, restoring green_weight=0" >&2
  set_weight 0
  exit 1
}

wait_for_soak() {
  local deadline=$((SECONDS + SOAK_SECONDS)) state
  while ((SECONDS < deadline)); do
    state=$(alarm_state)
    case "$state" in
      OK | INSUFFICIENT_DATA) ;;
      *) rollback "$1" ;;
    esac
    sleep "$POLL_SECONDS"
  done
}

main() {
  case "$(alarm_state)" in
    OK | INSUFFICIENT_DATA) ;;
    *) echo "guard: alarm already in ALARM before rollout starts" && rollback 0 ;;
  esac

  local step
  for step in $STEPS; do
    echo "guard: shifting ${step}% of traffic to green, soaking ${SOAK_SECONDS}s"
    set_weight "$step"
    wait_for_soak "$step"
  done
  echo "guard: green holds 100% of traffic"
}

main "$@"
