#!/usr/bin/env bash
# top_jobs.sh — Find top N users by job count from Slurm jobcomp log filtered by X days

# define parameters
LOG_FILE="/var/log/slurm_jobcomp.log"
TOP_N=5			# Default number of users
DAYS=0			# Default: all time
SAVE_FILE=""		# Default: nothing
DISPLAY_MODE="verbose"	# Default: verbose
OUTPUT_MODE="screen"	# Default: screen

## ARGUMENT PARSER ##
# Parse named arguments like users=10 days=30 display=dashboard output=screen
for arg in "$@"; do
  case $arg in
    users=*) TOP_N="${arg#*=}" ;;
    days=*) DAYS="${arg#*=}" ;;
    save=*) SAVE_FILE="${arg#*=}" ;;
    display=*) DISPLAY_MODE="${arg#*=}" ;;
    output=*) OUTPUT_MODE="${arg#*=}" ;;
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


# Calculate cutoff timestamp if DAYS is set
if (( DAYS > 0 )); then
  start_date=$(date -d "-$DAYS days" +"%Y-%m-%d")
  end_date=$(date +"%Y-%m-%d")
  date_range="past $DAYS days ($start_date to $end_date)"
else
  date_range="for all time"
fi

RESULT=$(awk -v cutoff="$cutoff" -v days="$DAYS" '
  {
    start = ""; user = "";
    for (i=1; i<=NF; i++) {
      if ($i ~ /^StartTime=/) {
        split($i, a, "=");
        gsub("T", " ", a[2]);
        start=a[2];
      }
      if ($i ~ /^UserId=/) {
        split($i, b, "=");
        user=b[2];
        sub(/\(.*/, "", user);
      }
    }

    if (user != "") {
      if (days == 0 || (start != "" && mktime(gensub(/[-:]/, " ", "g", start)) >= cutoff)) {
        count[user]++;
      }
    }
  }
  END {
    for (u in count) {
      printf "%s %d\n", u, count[u];
    }
  }
' "$LOG_FILE" | sort -k2 -nr | head -n "$TOP_N")

# Format output based on display mode
if [[ "$DISPLAY_MODE" == "dashboard" ]]; then
  HEADER="Top $TOP_N users by job count : $date_range"
  OUTPUT_TEXT="$HEADER"$'\n'"$RESULT"
else
  OUTPUT_TEXT="📊 Showing top $TOP_N users by job count from $LOG_FILE"$'\n'
  [[ "$DAYS" -gt 0 ]] && OUTPUT_TEXT+="🕒 Filtering jobs from the last $DAYS days"$'\n'
  OUTPUT_TEXT+=$'\n'"$RESULT"
fi

# Output destination logic
if [[ "$OUTPUT_MODE" == "screen" || "$OUTPUT_MODE" == "both" ]]; then
  echo "$OUTPUT_TEXT"
fi

if [[ "$OUTPUT_MODE" == "file" || "$OUTPUT_MODE" == "both" ]]; then
  if [[ -z "$SAVE_FILE" ]]; then
    SAVE_FILE="top_users_report.txt"
  fi
  echo "$OUTPUT_TEXT" > "$SAVE_FILE"
  echo "💾 Results saved to $SAVE_FILE"
fi
