export MATH_BACKEND=python
. ./bash_logging_with_timer.sh
# -------- Demo
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  echo "=== Bash Logging Library Demo ==="
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