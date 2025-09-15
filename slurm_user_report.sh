#!/usr/bin/env bash
# slurm_report.sh — Parse /var/log/slurm_jobcomp.log for a user's jobs, summarize states and durations.

set -u

LOG_FILE="${LOG_FILE:-/var/log/slurm_jobcomp.log}"
USER_ID="${1:-fkakembo}"
VERBOSE="${VERBOSE:-0}"

# Emoji state buckets
declare -A symbol_count=( ["✅"]=0 ["❌"]=0 ["🚫"]=0 ["⚠"]=0 )
total_duration=0
job_count=0

# Helper: print debug when VERBOSE=1
dbg() { (( VERBOSE )) && echo "[dbg] $*" >&2; }

# Helper: parse a key=value (handles comma or space separated fields)
# Extracts until first comma or space after '='.
kv() {
  # $1: key name, $2: line
  echo "$2" | grep -oP "$1=\K[^ ,]+" || true
}

# Ensure log file exists and readable
if [[ ! -r "$LOG_FILE" ]]; then
  echo "Error: log file not readable: $LOG_FILE" >&2
  exit 1
fi

matches=$(grep -c "UserId=${USER_ID}" "$LOG_FILE" || true)
if (( matches == 0 )); then
  echo "No jobs found for UserId=$USER_ID in $LOG_FILE"
  exit 0
fi

# Process lines for the user without subshell (process substitution)
while IFS= read -r line; do
  # Basic filter (cheap)
  [[ "$line" == *"UserId=${USER_ID}"* ]] || continue

  jobid=$(kv "JobId" "$line")
  state=$(kv "State" "$line")
  exitcode=$(kv "ExitCode" "$line")
  start=$(kv "Start" "$line")
  end=$(kv "End" "$line")

  dbg "line: $line"
  dbg "parsed: JobId=$jobid State=$state ExitCode=$exitcode Start=$start End=$end"

  # Guard: need start and end to compute duration
  if [[ -n "${start:-}" && -n "${end:-}" ]]; then
    # Normalize ISO8601 "YYYY-MM-DDTHH:MM:SS" -> "YYYY-MM-DD HH:MM:SS"
    start_norm="${start/T/ }"
    end_norm="${end/T/ }"

    # Convert to epoch (GNU date)
    if start_epoch=$(date -d "$start_norm" +%s 2>/dev/null) && end_epoch=$(date -d "$end_norm" +%s 2>/dev/null); then
      if (( end_epoch >= start_epoch )); then
        duration=$(( end_epoch - start_epoch ))
        total_duration=$(( total_duration + duration ))
        (( job_count++ ))
        dbg "duration(s)=$duration total=$total_duration jobs=$job_count"
      else
        dbg "skip: End before Start for JobId=$jobid"
      fi
    else
      dbg "skip: date parse failed for JobId=$jobid start=$start end=$end"
    fi
  else
    dbg "skip: missing Start/End for JobId=$jobid"
  fi

  # Tally state to emoji
  case "$state" in
    COMPLETED) ((symbol_count["✅"]++)) ;;
    FAILED)    ((symbol_count["❌"]++)) ;;
    CANCELLED|CANCELLED*) ((symbol_count["🚫"]++)) ;;
    TIMEOUT|NODE_FAIL|PREEMPTED|OUT_OF_MEMORY|BOOT_FAIL) ((symbol_count["⚠"]++)) ;;
    *) dbg "unmapped state: $state" ;;
  esac

done < <(grep "UserId=${USER_ID}" "$LOG_FILE")

# Output
echo "🔢 Job Status Summary for '$USER_ID':"
printf "✅ %d\n" "${symbol_count["✅"]}"
printf "❌ %d\n" "${symbol_count["❌"]}"
printf "🚫 %d\n" "${symbol_count["🚫"]}"
printf "⚠ %d\n" "${symbol_count["⚠"]}"

echo ""
echo "⏱️ Duration Summary:"
echo "Total jobs with duration: $job_count"

# Format HH:MM:SS
hms() {
  local s=$1
  printf "%02d:%02d:%02d" $((s/3600)) $(((s%3600)/60)) $((s%60))
}

echo "Total runtime: $total_duration seconds ($(hms "$total_duration"))"
if (( job_count > 0 )); then
  avg=$(( total_duration / job_count ))
  echo "Average runtime: $avg seconds ($(hms "$avg"))"
else
  echo "Average runtime: N/A"
fi

# Exit success
exit 0
