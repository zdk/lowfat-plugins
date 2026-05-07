#!/bin/sh
# terraform-compact — compact terraform/tf/tofu output for LLM contexts.
# Strips refresh/still-XYZ noise; keeps actions, summary, errors.

RAW=$(cat)
LEVEL="${LOWFAT_LEVEL:-full}"
ARGS="${LOWFAT_ARGS}"
EXIT="${LOWFAT_EXIT_CODE:-0}"

# Resolve real subcommand by skipping global flags like -chdir=..., -version.
# Fall back to $LOWFAT_SUBCOMMAND for callers that don't set $LOWFAT_ARGS (e.g. `plugin bench`).
SUB=""
for arg in $ARGS; do
  case "$arg" in
    -*) continue ;;
    *) SUB="$arg"; break ;;
  esac
done
[ -z "$SUB" ] && SUB="${LOWFAT_SUBCOMMAND}"

# Per-level row caps. Picked once, reused below.
case "$LEVEL" in
  ultra) PLAN=40;  APPLY=30;  INIT=10; STATE=30;  OUT=40  ;;
  lite)  PLAN=120; APPLY=100; INIT=60; STATE=200; OUT=120 ;;
  *)     PLAN=60;  APPLY=50;  INIT=30; STATE=80;  OUT=80  ;;
esac

# Non-zero exit: be conservative — keep error blocks intact, only drop the
# obvious refresh-state churn.
if [ "$EXIT" -ne 0 ]; then
  echo "$RAW" \
    | grep -vE ': (Refreshing state|Reading|Read complete after )' \
    | head -n 80
  exit 0
fi

case "$SUB" in
  plan)
    if [ "$LEVEL" = "ultra" ]; then
      # Just the verdict.
      OUT=$(echo "$RAW" | grep -E '^(Plan:|No changes\.|Error|Warning:)' | head -n 5)
      echo "${OUT:-terraform plan: ok}"
    else
      echo "$RAW" \
        | grep -vE ': (Refreshing state|Reading|Read complete after )' \
        | grep -vE '^(Note: Objects have changed|Terraform (will perform|detected|used)|(plan\. )?Resource actions are indicated|Unless you have made|Saved the plan to:|To perform exactly these actions,|    terraform apply )' \
        | grep -vE '^─+$' \
        | head -n "$PLAN"
    fi
    ;;
  apply|destroy)
    if [ "$LEVEL" = "ultra" ]; then
      OUT=$(echo "$RAW" | grep -E '^(Apply complete!|Destroy complete!|Error|Warning:)' | head -n 5)
      echo "${OUT:-terraform $SUB: ok}"
    else
      # Drop progress chatter (Still creating/destroying/modifying/reading).
      echo "$RAW" \
        | grep -vE ': (Refreshing state|Reading|Still (creating|destroying|modifying))\.\.\.' \
        | grep -vE ': (Creation|Modifications|Destruction|Read) complete after ' \
        | head -n "$APPLY"
    fi
    ;;
  init)
    if [ "$LEVEL" = "ultra" ]; then
      echo "$RAW" \
        | grep -E '(successfully initialized|Upgrading|Error|Warning:|^- (Installing|Using|Reusing|Finding))' \
        | head -n "$INIT"
    else
      # Strip post-success boilerplate ("You may now begin...", "If you ever set or change...",
      # "Terraform has created a lock file...") — keep the success line and provider list.
      echo "$RAW" \
        | grep -E '(Initializing|Successfully configured|^- (Installing|Installed|Using|Reusing|Finding|Downloading)|successfully initialized|Upgrading|Error|Warning:)' \
        | head -n "$INIT"
    fi
    ;;
  validate)
    if [ "$LEVEL" = "ultra" ]; then
      echo "$RAW" | grep -E '(Success!|Error|Warning:)' | head -n 10
    else
      echo "$RAW" | head -n 40
    fi
    ;;
  fmt)
    # Either empty (clean) or a short list of reformatted files.
    echo "$RAW" | head -n 50
    ;;
  state)
    # state list/show: structured-ish, just cap.
    echo "$RAW" | head -n "$STATE"
    ;;
  output)
    # Outputs are usually structured (key = value or JSON); keep as-is up to cap.
    echo "$RAW" | head -n "$OUT"
    ;;
  *)
    echo "$RAW" | head -n 30
    ;;
esac
