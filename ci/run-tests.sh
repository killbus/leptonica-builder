#!/usr/bin/env bash

set -euo pipefail

readonly CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

shopt -s nullglob
scripts=("$CI_DIR"/*.sh)
tests=("$CI_DIR"/tests/*_test.sh)

((${#tests[@]} > 0)) || {
  printf 'no CI tests discovered under %s/tests\n' "$CI_DIR" >&2
  exit 1
}

for script in "${scripts[@]}"; do
  bash -n "$script"
done

for test_script in "${tests[@]}"; do
  printf 'running %s\n' "${test_script#"$CI_DIR/"}"
  bash "$test_script"
done
