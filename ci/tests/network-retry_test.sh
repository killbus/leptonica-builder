#!/usr/bin/env bash

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
readonly RETRY="$TEST_DIR/../network-retry.sh"
WORK_DIR="$(mktemp -d)"
readonly WORK_DIR
readonly BUILD_WORKFLOW="$TEST_DIR/../../.github/workflows/build.yml"
readonly RELEASE_WORKFLOW="$TEST_DIR/../../.github/workflows/release.yml"
readonly INSTALL_AGE="$TEST_DIR/../install-age.sh"
readonly PROMOTION="$TEST_DIR/../promote-accepted-build.sh"

cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

fail() {
  printf 'network retry test: %s\n' "$*" >&2
  exit 1
}

# shellcheck source=ci/network-retry.sh
source "$RETRY"

flaky_command() {
  local count=0
  [[ ! -f "$WORK_DIR/flaky-count" ]] || count="$(<"$WORK_DIR/flaky-count")"
  count=$((count + 1))
  printf '%s' "$count" >"$WORK_DIR/flaky-count"
  ((count >= 3))
}

partial_then_complete() {
  local count=0
  [[ ! -f "$WORK_DIR/output-count" ]] || count="$(<"$WORK_DIR/output-count")"
  count=$((count + 1))
  printf '%s' "$count" >"$WORK_DIR/output-count"
  if ((count < 3)); then
    printf 'partial-%s\n' "$count"
    return 23
  fi
  printf 'complete\n'
}

always_fails() {
  local count=0
  [[ ! -f "$WORK_DIR/failure-count" ]] || count="$(<"$WORK_DIR/failure-count")"
  count=$((count + 1))
  printf '%s' "$count" >"$WORK_DIR/failure-count"
  return 29
}

succeeds_after_twelve() {
  local count=0
  [[ ! -f "$WORK_DIR/unbounded-count" ]] || count="$(<"$WORK_DIR/unbounded-count")"
  count=$((count + 1))
  printf '%s' "$count" >"$WORK_DIR/unbounded-count"
  if ((count < 12)); then
    return 22
  fi
}

NETWORK_RETRY_MAX_ATTEMPTS=3 NETWORK_RETRY_INITIAL_DELAY_SECONDS=0 \
  NETWORK_RETRY_MAX_DELAY_SECONDS=0 network_retry 'flaky request' flaky_command
[[ "$(<"$WORK_DIR/flaky-count")" == 3 ]] || fail 'successful retry used the wrong attempt count'

NETWORK_RETRY_MAX_ATTEMPTS=3 NETWORK_RETRY_INITIAL_DELAY_SECONDS=0 \
  NETWORK_RETRY_MAX_DELAY_SECONDS=0 network_retry_to_file \
    "$WORK_DIR/response" 'partial response request' partial_then_complete
[[ "$(<"$WORK_DIR/response")" == complete ]] || \
  fail 'failed-attempt output contaminated the successful response'

if NETWORK_RETRY_MAX_ATTEMPTS=3 NETWORK_RETRY_INITIAL_DELAY_SECONDS=0 \
  NETWORK_RETRY_MAX_DELAY_SECONDS=0 network_retry 'permanent request failure' always_fails; then
  fail 'retry unexpectedly accepted a permanently failing command'
fi
[[ "$(<"$WORK_DIR/failure-count")" == 3 ]] || fail 'retry limit used the wrong attempt count'

unset NETWORK_RETRY_MAX_ATTEMPTS
NETWORK_RETRY_INITIAL_DELAY_SECONDS=0 NETWORK_RETRY_MAX_DELAY_SECONDS=0 \
  network_retry 'extended temporary failure' succeeds_after_twelve
[[ "$(<"$WORK_DIR/unbounded-count")" == 12 ]] || \
  fail 'default retry stopped before the temporary failure recovered'

grep -F 'readonly NETWORK_RETRY_DEFAULT_MAX_ATTEMPTS=0' "$RETRY" >/dev/null || \
  fail 'default network retry is not unbounded'
# shellcheck disable=SC2016
grep -F 'network_retry_to_file "$archive"' "$INSTALL_AGE" >/dev/null || \
  fail 'age download bypasses the unbounded network retry contract'
if grep -R -F 'NETWORK_RETRY_MAX_ATTEMPTS=' "$TEST_DIR/../../.github" "$TEST_DIR/.." \
  --exclude=network-retry.sh --exclude-dir=tests >/dev/null; then
  fail 'production code sets a finite network retry limit'
fi
grep -F "source .builder-ci/ci/network-retry.sh" "$BUILD_WORKFLOW" >/dev/null || \
  fail 'build workflow does not load the network retry contract'
if sed -n '/^  build-info-contract-test:/,/^  build:/p' "$BUILD_WORKFLOW" | \
  grep -F 'install-age.sh' >/dev/null; then
  fail 'push-only contract tests install network tooling'
fi
grep -F "network_retry 'install pinned emsdk toolchain'" "$BUILD_WORKFLOW" >/dev/null || \
  fail 'emsdk toolchain installation bypasses the network retry contract'
emsdk_install_block=$(sed -n '/- name: Install emsdk/,/- name: Build release target/p' "$BUILD_WORKFLOW")
grep -F 'prepare_emsdk_checkout_once() {' <<<"$emsdk_install_block" >/dev/null || \
  fail 'emsdk checkout retry does not use an attempt-local preparation function'
grep -F 'rm -rf tmp/emsdk' <<<"$emsdk_install_block" >/dev/null || \
  fail 'emsdk checkout retry does not clear partial checkout state'
grep -F 'git clone --depth 1' <<<"$emsdk_install_block" >/dev/null || \
  fail 'emsdk checkout retry does not recreate the clone'
# This assertion intentionally matches a literal workflow expression.
# shellcheck disable=SC2016
grep -F 'git -C tmp/emsdk fetch --depth 1 origin ${{ steps.pins.outputs.emsdk_commit }}' \
  <<<"$emsdk_install_block" >/dev/null || \
  fail 'emsdk checkout retry does not fetch the pinned revision'
grep -F "network_retry 'prepare pinned emsdk checkout'" \
  <<<"$emsdk_install_block" >/dev/null || \
  fail 'emsdk clone and pinned fetch do not share one clean retry boundary'
if grep -F "network_retry 'fetch pinned emsdk revision'" \
  <<<"$emsdk_install_block" >/dev/null; then
  fail 'emsdk pinned fetch still retries against a reused checkout'
fi
build_release_block=$(sed -n '/- name: Build release target/,/- name: Smoke test/p' "$BUILD_WORKFLOW")
grep -F 'source ./tmp/emsdk/emsdk_env.sh' <<<"$build_release_block" >/dev/null || \
  fail 'release build does not load the activated emsdk environment'
grep -F "source ci/network-retry.sh" "$RELEASE_WORKFLOW" >/dev/null || \
  fail 'release workflow does not load the network retry contract'
grep -F 'network_retry_to_file candidate-transport.zip' "$RELEASE_WORKFLOW" >/dev/null || \
  fail 'candidate artifact download bypasses safe response retries'
grep -F 'delete_candidate_transport_once' "$RELEASE_WORKFLOW" >/dev/null || \
  fail 'candidate artifact deletion cannot reconcile an ambiguous success'
# This assertion intentionally matches a literal workflow expression.
# shellcheck disable=SC2016
grep -F 'actions/runs/$EXPECTED_WORKFLOW_RUN_ID/artifacts?per_page=100' \
  "$RELEASE_WORKFLOW" >/dev/null || \
  fail 'candidate artifact deletion does not use a 200-returning inventory probe'
# This assertion intentionally matches a literal shell expression.
# shellcheck disable=SC2016
grep -F 'source "$CI_DIR/network-retry.sh"' "$PROMOTION" >/dev/null || \
  fail 'promotion does not load the network retry contract'
grep -F 'ensure_production_release_once' "$PROMOTION" >/dev/null || \
  fail 'release publication cannot reconcile an ambiguous create'
grep -F "gh release delete" "$PROMOTION" >/dev/null && \
  fail 'release publication still uses non-idempotent delete-before-create'

printf 'network retry tests passed\n'
