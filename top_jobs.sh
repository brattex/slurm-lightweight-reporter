#!/usr/bin/env bash
# top_jobs.sh — Find top N users by job count from Slurm jobcomp log filtered by X days

# define parameters
LOG_FILE="/var/log/slurm_jobcomp.log"
TOP_N=5				# Default number of users
DAYS=0				# Default: all time
SAVE_FILE="./dashboard.log"	# Default: fallback value
DISPLAY_MODE="verbose"		# Default: verbose
OUTPUT_MODE="screen"		# Default: screen
WRITE_MODE="append"  		# default behavior


## ARGUMENT PARSER ##
# Parse named arguments like users=10 days=30 display=dashboard output=screen
for arg in "$@"; do
  case $arg in
    users=*) TOP_N="${arg#*=}" ;;
    days=*) DAYS="${arg#*=}" ;;
    save=*) SAVE_FILE="${arg#*=}" ;;	# overrides default if provided
    display=*) DISPLAY_MODE="${arg#*=}" ;;
    output=*) OUTPUT_MODE="${arg#*=}" ;;
    new) WRITE_MODE="new" ;; 		# overwrite mode
    append) WRITE_MODE="append" ;;	# optional, default
    *)
      echo "❌ Unknown parameter: $arg"
      echo "Usage: $0 [users=N] [days=X] [display=dashboard|verbose] [output=file|screen|both] [save=path]"
      echo "Example: $0 users=10 days=30 display=dashboard"
      exit 1
      ;;
  esac
done

# HELPER LINES
if [[ "$DISPLAY_MODE" != "dashboard" ]]; then
  echo "---"
  echo "USAGE:  $0 users=N days=X display=[verbose|dashboard] output=[screen|file|both]"
  echo
  echo "* users=N         -> number of top users to show [default: 5]"
  echo "* days=X          -> filter jobs from past X days [default: all time]"
  echo "* display=...     -> verbose (full output) or dashboard (minimal)"
  echo "* output=...      -> screen, file, or both"
  echo "* save=...        -> path to save file if output includes 'file'"
  echo "* edit LOG_FILE   -> set path to jobcomp log inside script"
  echo
fi

# define pretty symbols (TODO: pretty)
declare -A STATUS_SYMBOL=(
  [COMPLETED]="✅"
  [FAILED]="❌"
  [CANCELLED]="🚫"
  [TIMEOUT]="🕒"
  [NODE_FAIL]="💥"
  [OUT_OF_MEMORY]="⚠️"
#  [PENDING]="…"
#  [RUNNING]="▶"
)

# Fixed display order
#STATUS_ORDER=(COMPLETED FAILED CANCELLED TIMEOUT NODE_FAIL OUT_OF_MEMORY PENDING RUNNING)
# define display order by symbol
SYMBOL_ORDER=(✅ ❌ 🚫 🕒 ⚠️ 💥)


# Validate inputs

# users=
if ! [[ "$TOP_N" =~ ^[0-9]+$ ]] || (( TOP_N <= 0 )); then
  echo "❌ Invalid number= value: must be a positive integer"
  exit 1
fi

# days=
if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || (( DAYS < 0 )); then
  echo "❌ Invalid days= value: must be zero or positive integer"
  exit 1
fi

if ! [[ "$DISPLAY_MODE" =~ ^(dashboard|verbose)$ ]]; then
  echo "❌ Invalid display= value: must be 'dashboard' or 'verbose'"
  exit 1
fi

if ! [[ "$OUTPUT_MODE" =~ ^(file|screen|both)$ ]]; then
  echo "❌ Invalid output= value: must be 'file', 'screen', or 'both'"
  exit 1
fi


# Calculate cutoff timestamp if DAYS is set
if (( DAYS > 0 )); then
  start_date=$(date -d "-$DAYS days" +"%Y-%m-%d")
  end_date=$(date +"%Y-%m-%d")
  date_range="past $DAYS days ($start_date to $end_date)"
  cutoff=$(date -d "$start_date" +"%s")

else
  date_range="for all time"
  cutoff=0
fi


# ─────────────────────────────────────────────────────────────────────────────
# overall job summary: total and per-state counts
# ─────────────────────────────────────────────────────────────────────────────
read -r total completed_cnt failed_cnt cancelled_cnt timeout_cnt node_fail_cnt oome_cnt < <(
  awk -v cutoff="$cutoff" -v days="$DAYS" '
    function to_epoch(ts) { gsub("T"," ",ts); return mktime(gensub(/[-:]/," ","g",ts)); }
    /^JobId=/ {
      # filter by days if requested
      if (days==0 || (match($0, /StartTime=([^ ]+)/,a) && to_epoch(a[1]) >= cutoff)) {
        total++
        match($0, /JobState=([^ ]+)/,s)
        state = s[1]
        if      (state=="COMPLETED")     completed++
        else if (state=="FAILED")        failed++
        else if (state=="CANCELLED")     cancelled++
        else if (state=="TIMEOUT")       timeout++
        else if (state=="NODE_FAIL")     node_fail++
        else if (state=="OUT_OF_MEMORY") oome++
      }
    }
    END {
      # print in fixed order: total then each state
      print total, completed, failed, cancelled, timeout, node_fail, oome
    }
  ' "$LOG_FILE"
)

# map raw counts into symbols
SUMMARY_LINE="TOTAL Jobs:${total}"
SUMMARY_LINE+=" ✅:${completed_cnt}"
SUMMARY_LINE+=" ❌:${failed_cnt}"
SUMMARY_LINE+=" 🚫:${cancelled_cnt}"
SUMMARY_LINE+=" 🕒:${timeout_cnt}"
SUMMARY_LINE+=" 💥:${node_fail_cnt}"
SUMMARY_LINE+=" ⚠️:${oome_cnt}"



# pretty -- counting job states
RESULT=$(awk -v cutoff="$cutoff" -v days="$DAYS" '
  function to_epoch(ts) {
    gsub("T", " ", ts)
    return mktime(gensub(/[-:]/, " ", "g", ts))
  }

  {
    user = ""; state = ""; start = ""
    for (i=1; i<=NF; i++) {
      if ($i ~ /^UserId=/) {
        split($i, a, "="); user=a[2]; sub(/\(.*/, "", user)
      }
      if ($i ~ /^JobState=/) {
        split($i, b, "="); state=b[2]
      }
      if ($i ~ /^StartTime=/) {
        split($i, c, "="); start=c[2]
      }
    }

    if (user != "" && state != "") {
      if (days == 0 || (start != "" && to_epoch(start) >= cutoff)) {
        count[user]++
        status[user,state]++
      }
    }
  }

  END {
    for (u in count) {
      printf "%s %d", u, count[u]
      for (s in status) {
        split(s, parts, SUBSEP)
        if (parts[1] == u) {
          printf " %s:%d", parts[2], status[s]
        }
      }
      printf "\n"
    }
  }
' "$LOG_FILE" | sort -k2 -nr | head -n "$TOP_N")

### post-process pretty symbols and in fixed symbol order
FORMATTED_RESULT=$(while read -r user total rest; do
  # map raw state to count
  declare -A raw_state=()
  for pair in $rest; do
    state="${pair%%:*}"
    count="${pair##*:}"
    raw_state["$state"]="$count"
  done

  # Group counts by symbol
  declare -A grouped=()
  for state in "${!STATUS_SYMBOL[@]}"; do
    symbol="${STATUS_SYMBOL[$state]}"
    count="${raw_state[$state]}"
    [[ -n "$count" ]] && grouped["$symbol"]=$((grouped["$symbol"] + count))
  done

  # Print row with tab indent and fixed symbol order and include explicit 0s for alignment
  printf "%-12s\t%4d" "$user" "$total"
  for symbol in "${SYMBOL_ORDER[@]}"; do
    count="${grouped[$symbol]:-0}"
    printf "\t%s:%d" "$symbol" "$count"
  done
  printf "\n"
done <<< "$RESULT")


# Format output based on display mode
if [[ "$DISPLAY_MODE" == "dashboard" ]]; then
  HEADER="Top $TOP_N users by job count : $date_range"
#  OUTPUT_TEXT="$HEADER"$'\n'"$RESULT"
#  OUTPUT_TEXT="$HEADER"$'\n'"$FORMATTED_RESULT"
  OUTPUT_TEXT="$SUMMARY_LINE"$'\n'$HEADER$'\n'"$FORMATTED_RESULT"
else
  OUTPUT_TEXT="$SUMMARY_LINE"$'\n\n'
  OUTPUT_TEXT+="📊 Showing top $TOP_N users by job count from $LOG_FILE"$'\n'
  [[ "$DAYS" -gt 0 ]] && OUTPUT_TEXT+="🕒 Filtering jobs from the last $DAYS days"$'\n'
  OUTPUT_TEXT+=$'\n'"$FORMATTED_RESULT"
fi

# Output destination logic
if [[ "$OUTPUT_MODE" == "screen" || "$OUTPUT_MODE" == "both" ]]; then
  echo "$OUTPUT_TEXT"
fi

if [[ "$OUTPUT_MODE" == "file" || "$OUTPUT_MODE" == "both" ]]; then
  if [[ "$WRITE_MODE" == "new" ]]; then
    { 
      echo "$OUTPUT_TEXT"
      echo 	# adds a blank line at the end
    } > "$SAVE_FILE"
    echo "🆕 Overwrote file: $SAVE_FILE"
  else
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    {
  #  echo -e "\n--- Report generated at $timestamp ---" >> "$SAVE_FILE"
      echo "$OUTPUT_TEXT" 
      echo 	# blank line
    } >> "$SAVE_FILE"
    echo "📎 Appended results to: $SAVE_FILE"
  fi
fi
