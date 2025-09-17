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

# format_time function for HH:MM:SS
format_time() {
  local s=$1
  printf "%02d:%02d:%02d" $((s/3600)) $(( (s%3600)/60 )) $((s%60))
}



# Calculate cutoff timestamp if DAYS is set
if (( DAYS > 0 )); then
  start_date=$(date -d "-$DAYS days" +"%Y-%m-%d")
  end_date=$(date +"%Y-%m-%d")
  date_range="past $DAYS days ($start_date to $end_date)"
else
  date_range="for all time"
fi

# set cutoff as a number
cutoff=$(date -d "-$DAYS days" +"%s")   

RESULT=$(awk -v cutoff="$cutoff" -v days="$DAYS" '
  function to_epoch(ts) {
    gsub("T", " ", ts)
    return mktime(gensub(/[-:]/, " ", "g", ts))
  }

  {
    start = ""; end = ""; user = ""
    for (i=1; i<=NF; i++) {
      if ($i ~ /^StartTime=/) {
        split($i, a, "="); start=a[2]
      }
      if ($i ~ /^EndTime=/) {
        split($i, b, "="); end=b[2]
      }
      if ($i ~ /^UserId=/) {
        split($i, c, "="); user=c[2]; sub(/\(.*/, "", user)
      }
    }

    if (user != "" && start != "" && end != "") {
      start_epoch = to_epoch(start)
      end_epoch = to_epoch(end)
      runtime = end_epoch - start_epoch

      if (runtime > 0 && (days == 0 || start_epoch >= cutoff)) {
        total[user] += runtime
      }
    }
  }

  END {
    for (u in total) {
      printf "%s %d\n", u, total[u]
    }
  }
' "$LOG_FILE" | sort -k2 -nr | head -n "$TOP_N")

# convert to HH:MM:SS
FORMATTED_RESULT=$(while read -r user secs; do
  printf "%-10s %s\n" "$user" "$(format_time "$secs")"
done <<< "$RESULT")


# Format output based on display mode
if [[ "$DISPLAY_MODE" == "dashboard" ]]; then
  HEADER="Top $TOP_N users by job count : $date_range"
#  OUTPUT_TEXT="$HEADER"$'\n'"$RESULT"
  OUTPUT_TEXT="$HEADER"$'\n'"$FORMATTED_RESULT"
else
  OUTPUT_TEXT="📊 Showing top $TOP_N users by job count from $LOG_FILE"$'\n'
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
