#!/usr/bin/env bash
# top_res.sh — Find top N users by resource use from Slurm jobcomp log filtered by X days

# define parameters
LOG_FILE="/var/log/slurm_jobcomp.log"
TOP_N="${users:-5}"				# Default number of users
DAYS="${days:-0}"				# Default: all time
SAVE_FILE="${save:-resources.log}"			# Default: fallback value
DISPLAY_MODE="${display:-dashboard}" 	# Default: dashboard
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
# Format output based on display mode
#!/usr/bin/env bash
# … your arg-parse, validation, date-range setup, cutoff calc …

LOG_FILE="/var/log/slurm_jobcomp.log"

# -----------------------------------------------------------------------------
# 1) Produce Combined CPU+Mem top-N
# -----------------------------------------------------------------------------
# Need to determine formula for combined resource calculations and weightings
#RES_COMB=$(
#  gawk \
#    -v cutoff="$cutoff" -v topn="$TOP_N" -v sortkey=both \
#    -f top_res.awk "$LOG_FILE" \
#    | sort -t'|' -k1,1nr \
#    | head -n "$TOP_N" \
#    | cut -d'|' -f2- \
#    | sed 's/^ *//'
#)

# -----------------------------------------------------------------------------
# 2) Produce Top-N by CPU-hours only
# -----------------------------------------------------------------------------
RES_CPU=$(
  gawk \
    -v cutoff="$cutoff" -v topn="$TOP_N" -v sortkey=cpu \
    -f top_res.awk "$LOG_FILE" \
    | sort -t'|' -k1,1nr \
    | head -n "$TOP_N" \
    | cut -d'|' -f2- \
    | sed 's/^ *//'
)

# -----------------------------------------------------------------------------
# 3) Produce Top-N by Memory (GB-hours) only
# -----------------------------------------------------------------------------
RES_MEM=$(
  gawk \
    -v cutoff="$cutoff" -v topn="$TOP_N" -v sortkey=mem \
    -f top_res.awk "$LOG_FILE" \
    | sort -t'|' -k1,1nr \
    | head -n "$TOP_N" \
    | cut -d'|' -f2- \
    | sed 's/^ *//'
)

# -----------------------------------------------------------------------------
# 4) Build your dashboard blob
# -----------------------------------------------------------------------------
HEADER="📊 Showing top $TOP_N users by resource use from $LOG_FILE"
if (( DAYS > 0 )); then
  HEADER+=" (last $DAYS days: $date_range)"
fi

if [[ "$DISPLAY_MODE" != "dashboard" ]]; then
  OUTPUT_TEXT="$HEADER"$'\n\n'
fi
# Combined section
#OUTPUT_TEXT+="📊 Top $TOP_N Users by CPU-Hours and Memory (GB-Hours)"$'\n'"$RES_COMB"$'\n\n'

# CPU-only section
OUTPUT_TEXT+="📊 Top $TOP_N Users by CPU-Hours $date_range: "$'\n'"$RES_CPU"$'\n\n'

# Memory-only section
OUTPUT_TEXT+="📊 Top $TOP_N Users by Memory (GB-Hours) $date_range:"$'\n'"$RES_MEM"

# -----------------------------------------------------------------------------
# 5) Single sink to screen/file
# -----------------------------------------------------------------------------
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
