#!/usr/bin/env bash
# shellcheck shell=bash

# -------- Log levels
declare -gA LOG_LEVELS=([CRITICAL]=50 [ERROR]=40 [WARNING]=30 [INFO]=20 [DEBUG]=10 [NOTSET]=0)
LOG_LEVEL=${LOG_LEVEL:-20}

# -------- Colors (safe under set -u)
declare -gA LOG_COLORS=(
  [CRITICAL]=$'\033[1;37;41m' [ERROR]=$'\033[1;31m' [WARNING]=$'\033[1;33m'
  [INFO]=$'\033[1;32m' [DEBUG]=$'\033[1;34m' [RESET]=$'\033[0m'
)
USE_COLOR=1
if [[ -n ${NO_COLOR-} || -n ${NOCOLOR-} || ! -t 1 ]]; then USE_COLOR=0; fi

# -------- Stopwatch & spark
declare -g STOPWATCH_START=0 STOPWATCH_LAST=0
declare -ga TIMING_HISTORY=()
MAX_HISTORY=20

# -------- Math backend detection
# if [[ -n ${MATH_BACKEND-} || -n ${MATH_BACKEND-} || ! -t 1 ]]; then MATH_BACKEND=""; fi


# Probe helpers return 0 on success and set MATH_BACKEND
_probe_python_cmd() {  # $1 = python-like cmd (python3/python/py -3)
  local cmd=$1 out
  if ! command -v "${cmd%% *}" >/dev/null 2>&1; then return 1; fi
  # Use stdin to avoid shell-quoting games on -c; works on CPython and py launcher
  if out=$($cmd - <<<'print(2+2)' 2>/dev/null); then
    [[ $out == 4 ]] || return 1
    MATH_BACKEND="$cmd"
    return 0
  fi
  return 1
}

_probe_node() {  # prefers node if it really executes code
  local out
  if ! command -v node >/dev/null 2>&1; then return 1; fi
  if out=$(node -e 'console.log(2+2)' 2>/dev/null); then
    [[ $out == 4 ]] || return 1
    MATH_BACKEND="node"
    return 0
  fi
  return 1
}

_probe_bc() {
  local out
  if ! command -v bc >/dev/null 2>&1; then return 1; fi
  if out=$(printf '2+2\n' | bc -l 2>/dev/null); then
    [[ $out == 4 ]] || return 1
    MATH_BACKEND="bc"
    return 0
  fi
  return 1
}

_detect_math_backend() {
  # Respect user override if already set to a working backend
  case ${MATH_BACKEND-} in
    python3|python|'py -3'|node|bc|bash) : ;;
    *) MATH_BACKEND="bash";;
  esac

  if [[ -n $MATH_BACKEND ]]; then
    return
  fi

  MATH_BACKEND="bash"
  return

  # Dead code... bash math is now faster than launching a process.
  # Order tuned for Windows / Git Bash comfort first
  _probe_python_cmd python3 && return 0
  _probe_python_cmd python  && return 0
  _probe_python_cmd 'py -3' && return 0
  _probe_node               && return 0
  _probe_bc                 && return 0
  MATH_BACKEND="bash"
}

# Minimal math shim (only used when backend != bash)
_math() {
  local expr=$1
  case "$MATH_BACKEND" in
    python3|python) "$MATH_BACKEND" -c "print($expr)" 2>/dev/null ;;
    'py -3')        py -3 -c "print($expr)" 2>/dev/null ;;
    node)           node -e "console.log($expr)" 2>/dev/null ;;
    bc)             printf 'scale=12; %s\n' "$expr" | bc -l 2>/dev/null ;;
    bash|'')        printf '' ;;  # not used on bash path; stay harmless under set -e
  esac
}

# -------- Fast time (milliseconds)
# Prefer Bash 5's EPOCHREALTIME (fast, no subprocess). Else GNU date +%s%3N, else seconds*1000.
_now_ms() {
  # Fast path: Bash 5+ EPOCHREALTIME ("secs.microseconds")
  if [[ -n ${EPOCHREALTIME-} ]]; then
    local s us ms
    s=${EPOCHREALTIME%.*}
    us=${EPOCHREALTIME#*.}
    # sanitize and pad microseconds to 6 digits
    us=${us//[!0-9]/}
    while ((${#us} < 6)); do us="${us}0"; done
    # force base-10 to dodge octal interpretation (leading zeros)
    ms=$(( 10#$s * 1000 + 10#${us:0:3} ))
    printf '%d\n' "$ms"
    return
  fi

  # GNU date with milliseconds
  if date +%s%3N >/dev/null 2>&1; then
    date +%s%3N
    return
  fi

  # Portable seconds * 1000
  local secs
  printf -v secs '%(%s)T' -1
  printf '%d\n' $(( secs * 1000 ))
}

# -------- Duration formatting (pure integer math; no bc)
_format_duration() {
  local ms=$1
  [[ $ms =~ ^[0-9]+$ ]] || { printf '%sms' "$ms"; return; }
  if   (( ms < 1000 ));     then printf '%dms' "$ms"
  elif (( ms < 60000 ));    then local c=$(( (ms * 100) / 1000 )); printf '%d.%02ds' $((c/100)) $((c%100))
  elif (( ms < 3600000 ));  then local s=$((ms/1000)); printf '%dm%02ds' $((s/60)) $((s%60))
  else                          local s=$((ms/1000)); printf '%dh%02dm' $((s/3600)) $(((s%3600)/60))
  fi
}

# -------- Spark line
_generate_spark() {
  local -a values=("$@")
  local max=0 val idx spark=""
  local blocks=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
  for val in "${values[@]}"; do ((val > max)) && max=$val; done
  ((max==0)) && max=1
  for val in "${values[@]}"; do
    if [[ $MATH_BACKEND == bash ]]; then
      idx=$(( (val * 7) / max ))
    else
      local ratio idxf; ratio=$(_math "$val / $max"); idxf=$(_math "$ratio * 7"); idx=${idxf%%.*}; [[ -z $idx ]] && idx=0
    fi
    ((idx<0)) && idx=0; ((idx>7)) && idx=7
    if ((USE_COLOR)); then
      if   (( val * 2 < max ));      then spark+=$'\033[1;32m'${blocks[idx]}$'\033[0m'
      elif (( val * 3 > max * 2 ));  then spark+=$'\033[1;31m'${blocks[idx]}$'\033[0m'
      else                                spark+="${blocks[idx]}"
      fi
    else
      spark+="${blocks[idx]}"
    fi
  done
  printf '%b\n' "$spark"
}

# -------- Stopwatch
log_stopwatch_start() {
  _detect_math_backend
  local now; now=$(_now_ms)
  STOPWATCH_START=$now
  STOPWATCH_LAST=$now
  TIMING_HISTORY=()
}

# Compute elapsed & total using ONE timestamp (perf)
_get_elapsed_and_total() {
  local now=$(_now_ms)
  local elapsed=$(( now - STOPWATCH_LAST ))
  local total=$(( now - STOPWATCH_START ))
  STOPWATCH_LAST=$now
  printf '%d %d\n' "$elapsed" "$total"
}

# -------- Core logger
_log() {
  local level=$1; shift
  local level_num=${LOG_LEVELS[$level]}
  (( level_num >= LOG_LEVEL )) || return 0

  local elapsed total pair
  pair=$(_get_elapsed_and_total)
  elapsed=${pair%% *}
  total=${pair##* }

  TIMING_HISTORY+=("$elapsed")
  if ((${#TIMING_HISTORY[@]} > MAX_HISTORY)); then TIMING_HISTORY=("${TIMING_HISTORY[@]:1}"); fi

  local spark=""
  ((${#TIMING_HISTORY[@]} > 1)) && spark=$(_generate_spark "${TIMING_HISTORY[@]}")

  local timestamp color="" reset=""
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  if ((USE_COLOR)); then color=${LOG_COLORS[$level]}; reset=${LOG_COLORS[RESET]}; fi

  local elapsed_fmt total_fmt
  elapsed_fmt=$(_format_duration "$elapsed")
  total_fmt=$(_format_duration "$total")

  printf '%s [%b%-8s%b] [+%-8s / %-8s]' "$timestamp" "$color" "$level" "$reset" "$elapsed_fmt" "$total_fmt"
  [[ -n $spark ]] && printf ' [%b]' "$spark"
  printf ' %s\n' "$*"
}

# -------- Facades
log_debug()    { _log DEBUG    "$@"; }
log_info()     { _log INFO     "$@"; }
log_warning()  { _log WARNING  "$@"; }
log_error()    { _log ERROR    "$@"; }
log_critical() { _log CRITICAL "$@"; }

log_set_level() {
  local level=${1:-}
  if [[ -n ${LOG_LEVELS[$level]+x} ]]; then LOG_LEVEL=${LOG_LEVELS[$level]}; else printf 'Invalid log level: %s\n' "$level" >&2; return 1; fi
}

# -------- Demo
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "=== Bash Logging Library Demo ==="
  _detect_math_backend
  echo "Math backend: $MATH_BACKEND"
  echo
  set +e
  log_set_level DEBUG
  log_stopwatch_start
  log_debug "This is a debug message";  sleep 0.1
  log_info  "This is an info message";  sleep 0.2
  log_warning "This is a warning message"; sleep 0.05
  log_error "This is an error message";  sleep 0.3
  log_info  "Let's simulate some work..."
  for i in {1..10}; do
    log_debug "Processing item $i"
    if command -v awk >/dev/null 2>&1; then sleep "$(awk 'BEGIN{srand(); printf "%.3f", rand()*0.2}')"; else sleep 0.05; fi
  done
  log_critical "This is a critical message!"
  sleep 0.1
  log_info "Demo complete - spark shows timing patterns"
fi
