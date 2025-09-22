#!/usr/bin/env bash
# top_res.sh — Find top N users by resource use from Slurm jobcomp log filtered by X days

# define parameters
LOG_FILE="/var/log/slurm_jobcomp.log"
TOP_N="${users:-5}"				# Default number of users
DAYS="${days:-0}"				# Default: all time
SAVE_FILE="${save:-resources.log}"			# Default: fallback value
DISPLAY_MODE="${display:-dashboard}"		# Default: dashboard
OUTPUT_MODE="${output:-screen}"		# Default: screen
WRITE_MODE="new"  		# default behavior


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
  echo "		     followed by 'new' or 'append'"
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

# Output function
write() {
  echo -e "$A" >> "$SAVE_FILE"
}

## check if the output is file, then initialise the file with blank
# [[ "$OUTPUT" == "file" ]] && : > "$SAVE_FILE"

write "Top Users by CPU-Hours and Memory GB-Hours : past $DAYS days ($(date -d "-$DAYS days" +"%Y-%m-%d") to $(date +"%Y-%m-%d"))"

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

###################################################################
# SCRIPT SCOPE SPECIFIC
#
# Initialise aggregates

# Run the gawk job, then sort & head Top-N & strip the numeric key
gawk -v cutoff="$cutoff" -v topn="$TOP_N" -f top_res.awk "$LOG_FILE" \
  | sort -rn | head -n "$TOP_N" \
  | cut -c12- > ./res_section.txt


# -----------------------------------------------------------------------------
#  Stitch results together
# -----------------------------------------------------------------------------
HEADER="Top $TOP_N users by resource use : past $DAYS days ($(date -d "-$DAYS days" +"%Y-%m-%d") to $(date +"%Y-%m-%d"))"

# run gawk → sort → head in one shot and grab all the lines (with real newlines)
RES_SECTION=$(
  gawk -v cutoff="$cutoff" -v topn="$TOP_N" -f top_res.awk "$LOG_FILE" \
    | sort -rn \
    | head -n "$TOP_N" \
    | cut -c12-    # strip the padded sort key we added
)

# now append it to your dashboard blob
OUTPUT_TEXT+=$'\n'"Top $TOP_N Users by CPU-Hours and Memory (GB-Hours):"$'\n'"$RES_SECTION"


# 7) Final screen/file logic
if [[ "$OUTPUT_MODE" =~ screen|both ]]; then
  echo "$OUTPUT_TEXT"
fi
if [[ "$OUTPUT_MODE" =~ file|both ]]; then
  if [[ "$WRITE_MODE" == "new" ]]; then
    echo "$OUTPUT_TEXT" > "$SAVE_FILE"
    echo "🆕 Overwrote $SAVE_FILE"
  else
    echo "$OUTPUT_TEXT" >> "$SAVE_FILE"
    echo "📎 Appended to $SAVE_FILE"
  fi
fi

# Format output based on display mode
if [[ "$DISPLAY_MODE" == "dashboard" ]]; then
  HEADER="Top $TOP_N users by resource use : $date_range"
#  OUTPUT_TEXT="$HEADER"$'\n'"$RESULT"
  OUTPUT_TEXT="$HEADER"$'\n'"$FORMATTED_RESULT"
else
  OUTPUT_TEXT="📊 Showing top $TOP_N users by resource use from $LOG_FILE"$'\n'
  [[ "$DAYS" -gt 0 ]] && OUTPUT_TEXT+="🕒 Filtering jobs from the last $DAYS days"$'\n'
  OUTPUT_TEXT+=$'\n'"$FORMATTED_RESULT"
fi

OUTPUT_TEXT+=$'\n'"$RES_SECTION"



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
