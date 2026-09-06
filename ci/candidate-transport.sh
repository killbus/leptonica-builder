#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SHA256_PATTERN='^sha256:[0-9a-f]{64}$'
readonly SHA_PATTERN='^[0-9a-f]{40}$'
readonly RELEASE_ID_PATTERN='^release-v1-[0-9a-f]{64}$'
readonly TARGET_ID_PATTERN='^target-v1-[0-9a-f]{64}$'

fail() {
  printf 'candidate transport: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Usage: ci/candidate-transport.sh <command> [options]

Commands:
  prepare       Create an envelope-v1 candidate transport.
  inspect       Validate and print envelope-v1 transport metadata.
  materialize   Recover and validate a candidate transport.

prepare options:
  --input-dir DIR
  --output-dir DIR
  --recipient AGE_RECIPIENT
  --key-id ID
  --release-id ID
  --target-id ID
  --source-revision SHA
  --build-role dev|prod

materialize options:
  --transport-dir DIR
  --output-dir DIR
  --identity-file FILE
  --expected-key-id ID
  --expected-payload-digest sha256:HEX
  --expected-transport-digest sha256:HEX
  --release-id ID
  --target-id ID
  --source-revision SHA
  --build-role dev|prod

inspect options:
  --transport-dir DIR

The age executable is resolved from AGE_BIN or PATH. The workflow is
responsible for installing a pinned, checksum-verified age release.
EOF
  exit 2
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

require_directory() {
  [[ -d "$2" ]] || fail "$1 directory does not exist"
}

require_file() {
  [[ -f "$2" ]] || fail "$1 file does not exist"
}

require_non_empty() {
  [[ -n "$2" ]] || fail "$1 is required"
}

require_sha256_digest() {
  [[ "$2" =~ $SHA256_PATTERN ]] || fail "$1 is not a SHA-256 digest"
}

require_source_revision() {
  [[ "$2" =~ $SHA_PATTERN ]] || fail "$1 is not a source revision SHA"
}

require_release_id() {
  [[ "$2" =~ $RELEASE_ID_PATTERN ]] || fail "$1 is not a release-v1 identity"
}

require_target_id() {
  [[ "$2" =~ $TARGET_ID_PATTERN ]] || fail "$1 is not a target-v1 identity"
}

parse_options() {
  OPTIONS=()
  local option seen index
  while (($#)); do
    case "$1" in
      --*=*)
        option="${1%%=*}"
        OPTIONS+=("$option" "${1#*=}")
        shift
        ;;
      --*)
        (($# >= 2)) || fail "missing value for $1"
        option="$1"
        OPTIONS+=("$option" "$2")
        shift 2
        ;;
      *) fail "unexpected argument: $1" ;;
    esac

    seen=0
    for ((index = 0; index < ${#OPTIONS[@]}; index += 2)); do
      [[ "${OPTIONS[index]}" == "$option" ]] && ((seen += 1))
    done
    ((seen == 1)) || fail "duplicate option: $option"
  done
}

option_value() {
  local name="$1"
  local index
  for ((index = 0; index < ${#OPTIONS[@]}; index += 2)); do
    if [[ "${OPTIONS[index]}" == "$name" ]]; then
      printf '%s' "${OPTIONS[index + 1]}"
      return 0
    fi
  done
  return 1
}

required_option() {
  local value
  value="$(option_value "$1" || true)"
  require_non_empty "$1" "$value"
  printf '%s' "$value"
}

assert_known_options() {
  local option known
  for ((index = 0; index < ${#OPTIONS[@]}; index += 2)); do
    option="${OPTIONS[index]}"
    known=false
    for candidate in "$@"; do
      if [[ "$option" == "--$candidate" ]]; then
        known=true
        break
      fi
    done
    [[ "$known" == true ]] || fail "unknown option: $option"
  done
}

age_command() {
  if [[ -n "${AGE_BIN:-}" ]]; then
    printf '%s' "$AGE_BIN"
  else
    printf '%s' age
  fi
}

sha256_digest() {
  local file="$1"
  printf 'sha256:%s' "$(sha256sum "$file" | awk '{print $1}')"
}

validate_role() {
  [[ "$2" == dev || "$2" == prod ]] || fail "$1 must be dev or prod"
}

validate_transport_name() {
  [[ "$2" =~ ^[A-Za-z0-9._-]+$ ]] || fail "$1 contains unsupported characters"
}

validate_relative_members() {
  local archive="$1"
  local members_file="$2"
  local member component

  tar --null --list --file "$archive" >"$members_file"
  while IFS= read -r -d '' member; do
    [[ -n "$member" ]] || fail "archive contains an empty member name"
    [[ "$member" != /* ]] || fail "archive contains an absolute member name"
    IFS='/' read -ra components <<< "$member"
    for component in "${components[@]}"; do
      [[ "$component" != .. ]] || fail "archive contains a parent traversal member"
    done
  done <"$members_file"

  tar --list --verbose --file "$archive" >"$members_file.verbose"
  awk '$1 !~ /^[-d]/{ exit 1 }' "$members_file.verbose" ||
    fail "archive contains a link or unsupported member type"
}

create_candidate_archive() {
  local input_dir="$1"
  local output_file="$2"
  local uncompressed="${output_file%.gz}"

  tar \
    --sort=name \
    --mtime='UTC 1970-01-01' \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --format=posix \
    --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime \
    --directory "$input_dir" \
    --create \
    --file "$uncompressed" \
    .
  gzip -n -c "$uncompressed" >"$output_file"
  rm -f "$uncompressed"
}

write_binding_manifest() {
  local output="$1"
  local release_id="$2"
  local target_id="$3"
  local source_revision="$4"
  local build_role="$5"
  local payload_digest="$6"

  jq -S -n \
    --arg transport_profile envelope-v1 \
    --arg cipher_profile age-x25519-v1 \
    --arg release_id "$release_id" \
    --arg target_id "$target_id" \
    --arg source_revision "$source_revision" \
    --arg build_role "$build_role" \
    --arg payload_digest "$payload_digest" \
    '{
      transport_profile: $transport_profile,
      cipher_profile: $cipher_profile,
      release_id: $release_id,
      target_id: $target_id,
      source_revision: $source_revision,
      build_role: $build_role,
      payload_digest: $payload_digest
    }' >"$output"
}

prepare() {
  parse_options "$@"
  assert_known_options input-dir output-dir recipient key-id release-id target-id \
    source-revision build-role

  require_command jq
  require_command tar
  require_command gzip
  require_command sha256sum
  require_command "$(age_command)"

  local input_dir output_dir recipient key_id release_id target_id
  local source_revision build_role output_parent staged_output temp_dir
  local candidate_archive payload_digest payload_bin transport_digest age_bin
  input_dir="$(required_option --input-dir)"
  output_dir="$(required_option --output-dir)"
  recipient="$(required_option --recipient)"
  key_id="$(required_option --key-id)"
  release_id="$(required_option --release-id)"
  target_id="$(required_option --target-id)"
  source_revision="$(required_option --source-revision)"
  build_role="$(required_option --build-role)"

  require_directory "input" "$input_dir"
  validate_transport_name key-id "$key_id"
  require_release_id release-id "$release_id"
  require_target_id target-id "$target_id"
  require_source_revision source-revision "$source_revision"
  validate_role build-role "$build_role"
  [[ "$recipient" =~ ^age1[0-9a-z]+$ ]] || fail "recipient is not an age X25519 recipient"
  [[ ! -e "$output_dir" ]] || fail "output directory already exists"

  output_parent="$(dirname "$output_dir")"
  mkdir -p "$output_parent"
  temp_dir="$(mktemp -d "$output_parent/.candidate-transport.XXXXXX")"
  cleanup_prepare() { rm -rf "$temp_dir"; }
  trap cleanup_prepare EXIT

  candidate_archive="$temp_dir/candidate.tar.gz"
  create_candidate_archive "$input_dir" "$candidate_archive"
  payload_digest="$(sha256_digest "$candidate_archive")"

  write_binding_manifest "$temp_dir/binding.json" "$release_id" "$target_id" \
    "$source_revision" "$build_role" "$payload_digest"

  tar \
    --owner=0 \
    --group=0 \
    --numeric-owner \
    --format=posix \
    --directory "$temp_dir" \
    --create \
    --file "$temp_dir/container.tar" \
    binding.json candidate.tar.gz

  staged_output="$temp_dir/output"
  mkdir -p "$staged_output"
  payload_bin="$staged_output/payload.bin"
  age_bin="$(age_command)"
  "$age_bin" -r "$recipient" -o "$payload_bin" \
    "$temp_dir/container.tar"
  transport_digest="$(sha256_digest "$payload_bin")"

  jq -S -n \
    --arg transport_profile envelope-v1 \
    --arg cipher_profile age-x25519-v1 \
    --arg release_id "$release_id" \
    --arg target_id "$target_id" \
    --arg source_revision "$source_revision" \
    --arg build_role "$build_role" \
    --arg payload_digest "$payload_digest" \
    --arg transport_digest "$transport_digest" \
    --arg key_id "$key_id" \
    '{
      transport_profile: $transport_profile,
      cipher_profile: $cipher_profile,
      release_id: $release_id,
      target_id: $target_id,
      source_revision: $source_revision,
      build_role: $build_role,
      payload_digest: $payload_digest,
      transport_digest: $transport_digest,
      key_id: $key_id
    }' >"$staged_output/envelope.json"

  mv "$staged_output" "$output_dir"
  rm -rf "$temp_dir"
  trap - EXIT
}

validate_envelope() {
  local envelope="$1"
  local expected_key_id="$2"
  local expected_payload_digest="$3"
  local expected_transport_digest="$4"
  local expected_release_id="$5"
  local expected_target_id="$6"
  local expected_source_revision="$7"
  local expected_build_role="$8"

  jq -e \
    '. | type == "object" and
      (keys == ["build_role", "cipher_profile", "key_id", "payload_digest", "release_id", "source_revision", "target_id", "transport_digest", "transport_profile"]) and
      .transport_profile == "envelope-v1" and
      .cipher_profile == "age-x25519-v1" and
      (.release_id | type == "string" and test("^release-v1-[0-9a-f]{64}$")) and
      (.target_id | type == "string" and test("^target-v1-[0-9a-f]{64}$")) and
      (.source_revision | type == "string" and test("^[0-9a-f]{40}$")) and
      (.build_role == "dev" or .build_role == "prod") and
      (.payload_digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
      (.transport_digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
      (.key_id | type == "string" and test("^[A-Za-z0-9._-]+$"))' \
    "$envelope" >/dev/null || fail "envelope metadata is invalid"

  jq -e \
    --arg key_id "$expected_key_id" \
    --arg payload_digest "$expected_payload_digest" \
    --arg transport_digest "$expected_transport_digest" \
    --arg release_id "$expected_release_id" \
    --arg target_id "$expected_target_id" \
    --arg source_revision "$expected_source_revision" \
    --arg build_role "$expected_build_role" \
    '.key_id == $key_id and
      .payload_digest == $payload_digest and
      .transport_digest == $transport_digest and
      .release_id == $release_id and
      .target_id == $target_id and
      .source_revision == $source_revision and
      .build_role == $build_role' \
    "$envelope" >/dev/null || fail "envelope metadata does not match accepted evidence"
}

inspect() {
  parse_options "$@"
  assert_known_options transport-dir

  require_command jq
  require_command sha256sum

  local transport_dir envelope payload_bin actual_digest
  transport_dir="$(required_option --transport-dir)"
  require_directory "transport" "$transport_dir"
  envelope="$transport_dir/envelope.json"
  payload_bin="$transport_dir/payload.bin"
  require_file "envelope" "$envelope"
  require_file "payload" "$payload_bin"

  jq -e \
    '. | type == "object" and
      (keys == ["build_role", "cipher_profile", "key_id", "payload_digest", "release_id", "source_revision", "target_id", "transport_digest", "transport_profile"]) and
      .transport_profile == "envelope-v1" and
      .cipher_profile == "age-x25519-v1" and
      (.release_id | type == "string" and test("^release-v1-[0-9a-f]{64}$")) and
      (.target_id | type == "string" and test("^target-v1-[0-9a-f]{64}$")) and
      (.source_revision | type == "string" and test("^[0-9a-f]{40}$")) and
      (.build_role == "dev" or .build_role == "prod") and
      (.payload_digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
      (.transport_digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
      (.key_id | type == "string" and test("^[A-Za-z0-9._-]+$"))' \
    "$envelope" >/dev/null || fail "envelope metadata is invalid"

  actual_digest="$(sha256_digest "$payload_bin")"
  [[ "$actual_digest" == "$(jq -er '.transport_digest' "$envelope")" ]] ||
    fail "transport payload digest does not match envelope metadata"
  jq -S -c . "$envelope"
}

# Keep EXIT cleanup in the same scope as its temporary-path locals.
materialize() (
  parse_options "$@"
  assert_known_options transport-dir output-dir identity-file expected-key-id \
    expected-payload-digest expected-transport-digest release-id target-id \
    source-revision build-role

  require_command jq
  require_command tar
  require_command gzip
  require_command sha256sum
  require_command "$(age_command)"

  local transport_dir output_dir output_parent staged_output identity_file expected_key_id
  local expected_payload_digest expected_transport_digest release_id target_id
  local source_revision build_role envelope payload_bin temp_dir age_bin
  local container_dir container_archive candidate_archive actual_digest
  transport_dir="$(required_option --transport-dir)"
  output_dir="$(required_option --output-dir)"
  identity_file="$(required_option --identity-file)"
  expected_key_id="$(required_option --expected-key-id)"
  expected_payload_digest="$(required_option --expected-payload-digest)"
  expected_transport_digest="$(required_option --expected-transport-digest)"
  release_id="$(required_option --release-id)"
  target_id="$(required_option --target-id)"
  source_revision="$(required_option --source-revision)"
  build_role="$(required_option --build-role)"

  require_directory "transport" "$transport_dir"
  require_file "identity" "$identity_file"
  require_sha256_digest expected-payload-digest "$expected_payload_digest"
  require_sha256_digest expected-transport-digest "$expected_transport_digest"
  require_release_id release-id "$release_id"
  require_target_id target-id "$target_id"
  require_source_revision source-revision "$source_revision"
  validate_role build-role "$build_role"
  validate_transport_name key-id "$expected_key_id"

  envelope="$transport_dir/envelope.json"
  payload_bin="$transport_dir/payload.bin"
  require_file "envelope" "$envelope"
  require_file "payload" "$payload_bin"
  validate_envelope "$envelope" "$expected_key_id" "$expected_payload_digest" \
    "$expected_transport_digest" "$release_id" "$target_id" "$source_revision" \
    "$build_role"

  actual_digest="$(sha256_digest "$payload_bin")"
  [[ "$actual_digest" == "$expected_transport_digest" ]] ||
    fail "transport payload digest does not match accepted evidence"

  [[ ! -e "$output_dir" ]] || fail "output directory already exists"
  output_parent="$(dirname "$output_dir")"
  mkdir -p "$output_parent"
  temp_dir="$(mktemp -d "$output_parent/.candidate-materialize.XXXXXX")"
  cleanup_materialize() { rm -rf "$temp_dir"; }
  trap cleanup_materialize EXIT

  age_bin="$(age_command)"
  "$age_bin" -d -i "$identity_file" -o "$temp_dir/container.tar" \
    "$payload_bin"

  validate_relative_members "$temp_dir/container.tar" "$temp_dir/container-members"
  mapfile -t container_members < <(tar --list --file "$temp_dir/container.tar")
  [[ "${#container_members[@]}" == 2 ]] || fail "protected container has unexpected members"
  [[ "${container_members[0]}" == binding.json && "${container_members[1]}" == candidate.tar.gz ]] ||
    fail "protected container member order or names are invalid"

  container_dir="$temp_dir/container"
  mkdir -p "$container_dir"
  tar --extract --file "$temp_dir/container.tar" --directory "$container_dir" \
    --no-same-owner --no-same-permissions
  require_file "binding manifest" "$container_dir/binding.json"
  require_file "candidate archive" "$container_dir/candidate.tar.gz"

  jq -e \
    --arg release_id "$release_id" \
    --arg target_id "$target_id" \
    --arg source_revision "$source_revision" \
    --arg build_role "$build_role" \
    --arg payload_digest "$expected_payload_digest" \
    'type == "object" and
      (keys == ["build_role", "cipher_profile", "payload_digest", "release_id", "source_revision", "target_id", "transport_profile"]) and
      .transport_profile == "envelope-v1" and
      .cipher_profile == "age-x25519-v1" and
      .release_id == $release_id and
      .target_id == $target_id and
      .source_revision == $source_revision and
      .build_role == $build_role and
      .payload_digest == $payload_digest' \
    "$container_dir/binding.json" >/dev/null || fail "inner binding manifest does not match accepted evidence"

  actual_digest="$(sha256_digest "$container_dir/candidate.tar.gz")"
  [[ "$actual_digest" == "$expected_payload_digest" ]] ||
    fail "candidate payload digest does not match accepted evidence"

  validate_relative_members "$container_dir/candidate.tar.gz" "$temp_dir/candidate-members"
  staged_output="$temp_dir/output"
  mkdir -p "$staged_output"
  tar --extract --gzip --file "$container_dir/candidate.tar.gz" --directory "$staged_output" \
    --no-same-owner --no-same-permissions

  mv "$staged_output" "$output_dir"
  rm -rf "$temp_dir"
  trap - EXIT
)

main() {
  (($# >= 1)) || usage
  local command="$1"
  shift
  case "$command" in
    prepare) prepare "$@" ;;
    inspect) inspect "$@" ;;
    materialize) materialize "$@" ;;
    -h|--help|help) usage ;;
    *) fail "unknown command: $command" ;;
  esac
}

main "$@"
