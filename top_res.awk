# top_res.awk
# Usage: gawk -v cutoff=EPOCH -v topn=N -f top_res.awk logfile

BEGIN {
  FS = " "
  OFS = "\t"
  # Map Slurm states → symbols
  split("COMPLETED:✅ FAILED:❌ CANCELLED:🚫 TIMEOUT:🕒 NODE_FAIL:💥 OUT_OF_MEMORY:⚠️", m, " ")

  for (i in m) {
    split(m[i], p, ":")
    status_symbol[p[1]] = p[2]
  }
}

# ISO8601 to epoch seconds
function to_epoch(ts,    a) {
  gsub("T", " ", ts)
  gsub(/[-:]/, " ", ts)
  split(ts, a, " ")
  # mktime("YYYY MM DD HH MM SS")
  return mktime(a[1] " " a[2] " " a[3] " " a[4] " " a[5] " " a[6])
}

# Process only JobId= lines
/^JobId=/ {
  # extract fields
  match($0, /UserId=([^()]+)/,    U)
  match($0, /JobState=([^ ]+)/,   S)
  match($0, /StartTime=([^ ]+)/,  St)
  match($0, /EndTime=([^ ]+)/,    En)
  match($0, /cpu=([0-9]+)/,       C)
  match($0, /mem=([0-9]+)/,       M)
  user  = U[1]
  state = S[1]
  start = St[1]
  end   = En[1]
  cpu   = C[1]
  mem   = M[1]
  if (!user || !start || !end) next

  se = to_epoch(start)
  ee = to_epoch(end)
  if (se < cutoff || ee <= se) next
  elapsed = ee - se

  cpu_sec[user] += elapsed * cpu
  mem_sec[user] += elapsed * mem / 1024
  state_count[user "," state]++
}

END {
  # Output lines: user, cpu_hours, mem_hours, symbol:count…
  for (u in cpu_sec) {
    cpu_hr = cpu_sec[u] / 3600
    mem_hr = mem_sec[u] / 3600
    line = sprintf(" %-12s %8.2f CPU-hrs   %8.2f GB-hrs", u, cpu_hr, mem_hr)

    # append all symbols in fixed order
    for (sym in status_symbol) order[sym] = ++i  # capture order
    # Hard-code the order you want:
    split("✅ ❌ 🚫 🕒 💥 ⚠️", SORDER, " ")
    for (k=1; k<=length(SORDER); k++) {
      sym = SORDER[k]
      cnt = state_count[u "," key_state(sym)] + 0
      line = line OFS sym ":" cnt
    }
    # Prepend a sorting key
    printf "%f|%s\n", cpu_hr, line
  }
}
# Helper to invert status_symbol map
function key_state(sym,   s) {
  for (st in status_symbol) if (status_symbol[st] == sym) return st
  return ""
}
