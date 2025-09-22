#!/bin/bash

########################################
# GEN_DASHBOARD.SH
#
# A sample dashboard generator / testing tool
#
# ./gen_dashboard.sh [days]
#
# if no DAYS is specified at command line, it defaults to 14
#
########################################

# Optional: set number of days to filter
DAYS="${1:-14}"
LOGFILE="dashboard.log"

# Run top_jobs and capture output
TOP_JOBS_OUTPUT=$(./top_jobs.sh display=dashboard days=$DAYS)

# Run top_runtime and capture output
TOP_RUNTIME_OUTPUT=$(./top_runtime.sh display=dashboard days=$DAYS)

# Combine and write to dashboard.log
{
  echo "📊 Cluster Job Dashboard"
  echo "🗓️ Date Range:  Past  $DAYS days ($(date -d "-$DAYS days" +"%Y-%m-%d") to $(date +"%Y-%m-%d"))"
  echo
  # Job count summary
  echo "$TOP_JOBS_OUTPUT"
  echo
  # Runtime summary
  echo "$TOP_RUNTIME_OUTPUT"
  echo
} > $LOGFILE

# Add Resource usage summary
./top_res.sh display=dashboard days=$DAYS output=file save="$LOGFILE"
