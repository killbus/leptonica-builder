#!/usr/bin/env bash

set -euo pipefail

# All HTTP 4xx/5xx and transport failures are treated as transient at this
# boundary. A zero maximum means retry without an attempt limit; CI job
# timeouts remain the outer safety boundary. Tests may set a finite limit.
readonly NETWORK_RETRY_DEFAULT_MAX_ATTEMPTS=0
readonly NETWORK_RETRY_DEFAULT_INITIAL_DELAY_SECONDS=2
readonly NETWORK_RETRY_DEFAULT_MAX_DELAY_SECONDS=30

network_retry_fail() {
  printf 'network retry: %s\n' "$*" >&2
  return 2
}

network_retry_require_uint() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] || network_retry_fail "$name must be a non-negative integer"
}

network_retry() {
  if (($# < 2)); then
    network_retry_fail 'usage: network_retry <label> <command> [args...]'
    return $?
  fi

  local label="$1"
  shift
  local max_attempts="${NETWORK_RETRY_MAX_ATTEMPTS:-$NETWORK_RETRY_DEFAULT_MAX_ATTEMPTS}"
  local delay="${NETWORK_RETRY_INITIAL_DELAY_SECONDS:-$NETWORK_RETRY_DEFAULT_INITIAL_DELAY_SECONDS}"
  local max_delay="${NETWORK_RETRY_MAX_DELAY_SECONDS:-$NETWORK_RETRY_DEFAULT_MAX_DELAY_SECONDS}"
  local attempt=1
  local status

  network_retry_require_uint NETWORK_RETRY_MAX_ATTEMPTS "$max_attempts" || return $?
  network_retry_require_uint NETWORK_RETRY_INITIAL_DELAY_SECONDS "$delay" || return $?
  network_retry_require_uint NETWORK_RETRY_MAX_DELAY_SECONDS "$max_delay" || return $?
  if ((max_delay < delay)); then
    network_retry_fail \
      'NETWORK_RETRY_MAX_DELAY_SECONDS must be at least NETWORK_RETRY_INITIAL_DELAY_SECONDS'
    return $?
  fi

  while true; do
    if "$@"; then
      return 0
    else
      status=$?
    fi

    if ((max_attempts > 0 && attempt >= max_attempts)); then
      printf 'network retry: %s failed after %d attempts (exit %d)\n' \
        "$label" "$attempt" "$status" >&2
      return "$status"
    fi

    if ((max_attempts == 0)); then
      printf 'network retry: %s failed on attempt %d (exit %d); retrying in %ss\n' \
        "$label" "$attempt" "$status" "$delay" >&2
    else
      printf 'network retry: %s failed on attempt %d/%d (exit %d); retrying in %ss\n' \
        "$label" "$attempt" "$max_attempts" "$status" "$delay" >&2
    fi
    sleep "$delay"
    attempt=$((attempt + 1))
    if ((delay < max_delay)); then
      delay=$((delay * 2))
      ((delay <= max_delay)) || delay="$max_delay"
    fi
  done
}

_network_retry_write_file() {
  local output_file="$1"
  shift
  "$@" >"$output_file"
}

network_retry_to_file() {
  if (($# < 3)); then
    network_retry_fail 'usage: network_retry_to_file <output> <label> <command> [args...]'
    return $?
  fi

  local output_file="$1"
  local label="$2"
  shift 2
  local output_dir temporary_output
  output_dir="$(dirname "$output_file")"
  if [[ ! -d "$output_dir" ]]; then
    network_retry_fail "output directory does not exist: $output_dir"
    return $?
  fi
  temporary_output="$(mktemp "$output_dir/.network-response.XXXXXX")"

  if network_retry "$label" _network_retry_write_file "$temporary_output" "$@"; then
    mv "$temporary_output" "$output_file"
  else
    local status=$?
    rm -f "$temporary_output"
    return "$status"
  fi
}

network_retry_capture() {
  if (($# < 3)); then
    network_retry_fail 'usage: network_retry_capture <variable> <label> <command> [args...]'
    return $?
  fi

  local variable_name="$1"
  local label="$2"
  shift 2
  if [[ ! "$variable_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    network_retry_fail "invalid capture variable name: $variable_name"
    return $?
  fi

  local temporary_output
  temporary_output="$(mktemp)"
  if network_retry_to_file "$temporary_output" "$label" "$@"; then
    printf -v "$variable_name" '%s' "$(<"$temporary_output")"
    rm -f "$temporary_output"
  else
    local status=$?
    rm -f "$temporary_output"
    return "$status"
  fi
}

network_retry_main() {
  if (($# < 1)); then
    network_retry_fail 'usage: network-retry.sh <run|to-file> ...'
    return $?
  fi
  local mode="$1"
  shift

  case "$mode" in
    run) network_retry "$@" ;;
    to-file) network_retry_to_file "$@" ;;
    *) network_retry_fail "unknown mode: $mode" ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  network_retry_main "$@"
fi
