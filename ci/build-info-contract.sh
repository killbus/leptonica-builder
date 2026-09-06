#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SHA_PATTERN='^[0-9a-f]{40}$'
readonly RELEASE_ID_PATTERN='^release-v1-[0-9a-f]{64}$'
readonly TARGET_ID_PATTERN='^target-v1-[0-9a-f]{64}$'
readonly ARTIFACT_DIGEST_INPUT_PATTERN='^(sha256:)?[0-9a-f]{64}$'
readonly ARTIFACT_DIGEST_PATTERN='^sha256:[0-9a-f]{64}$'
readonly TIMESTAMP_PATTERN='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'

declare -A OPTIONS=()

fail() { printf 'build-info contract: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
Usage: ci/build-info-contract.sh <command> [options]

Commands:
  validate-source-manifest      Validate the public source release-set shape.
  print-release-matrix          Print the target matrix for a valid release set.
  create-candidate              Adapt source build-info into candidate evidence.
  attach-candidate-artifact     Bind transport and hosting artifact identities.
  accept-candidate-set          Validate and accept the complete target set.
  validate-transport-pair       Validate accepted evidence before materialization.
  validate-release-pair         Validate materialized and accepted build-info.
EOF
}

parse_options() {
  OPTIONS=()
  while (($# > 0)); do
    [[ "$1" == --* ]] || fail "expected an option, got '$1'"
    (($# >= 2)) || fail "option '$1' requires a value"
    local name="${1#--}"
    [[ -z "${OPTIONS[$name]+present}" ]] || fail "duplicate option '--$name'"
    OPTIONS[$name]="$2"
    shift 2
  done
}

assert_known_options() {
  local name allowed=" $* "
  for name in "${!OPTIONS[@]}"; do
    [[ "$allowed" == *" $name "* ]] || fail "unknown option '--$name'"
  done
}

required_option() {
  local name="$1" value="${OPTIONS[$1]:-}"
  [[ -n "$value" ]] || fail "missing required option '--$name'"
  printf '%s' "$value"
}

require_file() { [[ -f "$2" ]] || fail "$1 does not exist: $2"; }
require_directory() { [[ -d "$2" ]] || fail "$1 does not exist: $2"; }
require_sha() { [[ "$2" =~ $SHA_PATTERN ]] || fail "$1 is not a lowercase commit SHA"; }
require_release_id() { [[ "$2" =~ $RELEASE_ID_PATTERN ]] || fail "$1 is not a release-v1 identity"; }
require_target_id() { [[ "$2" =~ $TARGET_ID_PATTERN ]] || fail "$1 is not a target-v1 identity"; }
require_timestamp() { [[ "$2" =~ $TIMESTAMP_PATTERN ]] || fail "$1 is not UTC ISO-8601"; }
require_repository() { [[ "$2" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "$1 is not an owner/repository name"; }
require_contract_version() { [[ "$1" == 1 ]] || fail "unsupported source contract version '$1'"; }

candidate_artifact_name() {
  printf 'candidate-%s-%s-%s' "$1" "$2" "$3"
}

validate_source_manifest() {
  local manifest="$1" contract_version="$2" source_revision="$3" release_id="$4"
  require_file "source release-set manifest" "$manifest"
  require_contract_version "$contract_version"
  require_sha "source revision" "$source_revision"
  require_release_id "release ID" "$release_id"

  jq -e \
    --argjson contract_version "$contract_version" \
    --arg source_revision "$source_revision" \
    --arg release_id "$release_id" \
    '
      type == "object" and
      (keys == ["release_id", "schema_version", "source_revision", "targets"]) and
      .schema_version == $contract_version and
      .source_revision == $source_revision and
      .release_id == $release_id and
      (.targets | type == "array" and length > 0) and
      ([.targets[].target_id] == ([.targets[].target_id] | sort)) and
      ([.targets[].target_id] | unique | length) == (.targets | length) and
      ([.targets[] | select(.build_role == "dev")] | length) == 1 and
      ([.targets[] | select(.build_role == "prod")] | length) >= 1 and
      all(.targets[];
        type == "object" and
        (keys == ["build_role", "outputs", "target_id", "transport_profile"]) and
        (.target_id | type == "string" and test("^target-v1-[0-9a-f]{64}$")) and
        (.build_role == "dev" or .build_role == "prod") and
        .outputs == ["leptonica.wasm", "leptonica.mjs", "build-info.json"] and
        .transport_profile == "envelope-v1")
    ' "$manifest" >/dev/null || fail "source release-set manifest is invalid"
}

manifest_target() {
  jq -ec --arg target_id "$2" \
    '.targets | map(select(.target_id == $target_id)) | if length == 1 then .[0] else error("target not found") end' \
    "$1" || fail "target is not present exactly once in the release set"
}

validate_source_build_info() {
  local source_build_info="$1" contract_version="$2" release_id="$3"
  local source_revision="$4" target_json="$5"
  require_file "source build-info" "$source_build_info"
  jq -e \
    --argjson contract_version "$contract_version" \
    --arg release_id "$release_id" \
    --arg source_revision "$source_revision" \
    --argjson target "$target_json" \
    '
      type == "object" and
      (keys == ["build_role", "release_id", "schema_version", "source_revision", "target_id", "transport_profile"]) and
      .schema_version == $contract_version and
      .release_id == $release_id and
      .source_revision == $source_revision and
      .target_id == $target.target_id and
      .build_role == $target.build_role and
      .transport_profile == $target.transport_profile
    ' "$source_build_info" >/dev/null || fail "source build-info does not match the release-set target"
}
validate_candidate_shape() {
  local manifest="$1"
  require_file "candidate manifest" "$manifest"
  jq -e --arg sha "$SHA_PATTERN" --arg timestamp "$TIMESTAMP_PATTERN" '
    type == "object" and
    (keys == ["artifact_status", "build_role", "build_timestamp", "builder_sha", "evidence_version", "expected_outputs", "leptonica_pin_sha", "release_id", "repository", "source_contract_version", "source_revision", "target_id", "transport_profile", "workflow_run_attempt", "workflow_run_id", "workflow_run_number"]) and
    .evidence_version == 1 and .artifact_status == "candidate" and
    .source_contract_version == 1 and
    (.release_id | type == "string" and test("^release-v1-[0-9a-f]{64}$")) and
    (.source_revision | type == "string" and test($sha)) and
    (.target_id | type == "string" and test("^target-v1-[0-9a-f]{64}$")) and
    (.build_role == "dev" or .build_role == "prod") and
    .expected_outputs == ["leptonica.wasm", "leptonica.mjs", "build-info.json"] and
    .transport_profile == "envelope-v1" and
    (.build_timestamp | type == "string" and test($timestamp)) and
    (.workflow_run_id | type == "string" and length > 0) and
    (.workflow_run_number | type == "string" and length > 0) and
    (.workflow_run_attempt | type == "string" and length > 0) and
    (.repository | type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and
    (.builder_sha | type == "string" and test($sha)) and
    (.leptonica_pin_sha | type == "string" and test($sha))
  ' "$manifest" >/dev/null || fail "candidate manifest has an invalid shape: $manifest"
}

validate_evidence_shape() {
  local manifest="$1"
  require_file "candidate evidence" "$manifest"
  jq -e --arg sha "$SHA_PATTERN" --arg timestamp "$TIMESTAMP_PATTERN" '
    type == "object" and
    (keys == ["artifact_status", "build_role", "build_timestamp", "builder_sha", "candidate_artifact", "cipher_profile", "evidence_version", "expected_outputs", "key_id", "leptonica_pin_sha", "payload_digest", "release_id", "repository", "source_contract_version", "source_revision", "target_id", "transport_digest", "transport_profile", "workflow_run_attempt", "workflow_run_id", "workflow_run_number"]) and
    .evidence_version == 1 and .artifact_status == "candidate" and
    .source_contract_version == 1 and
    (.release_id | type == "string" and test("^release-v1-[0-9a-f]{64}$")) and
    (.source_revision | type == "string" and test($sha)) and
    (.target_id | type == "string" and test("^target-v1-[0-9a-f]{64}$")) and
    (.build_role == "dev" or .build_role == "prod") and
    .expected_outputs == ["leptonica.wasm", "leptonica.mjs", "build-info.json"] and
    .transport_profile == "envelope-v1" and .cipher_profile == "age-x25519-v1" and
    (.key_id | type == "string" and test("^[A-Za-z0-9._-]+$")) and
    (.payload_digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
    (.transport_digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
    (.build_timestamp | type == "string" and test($timestamp)) and
    (.workflow_run_id | type == "string" and length > 0) and
    (.workflow_run_number | type == "string" and length > 0) and
    (.workflow_run_attempt | type == "string" and length > 0) and
    (.repository | type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and
    (.builder_sha | type == "string" and test($sha)) and
    (.leptonica_pin_sha | type == "string" and test($sha)) and
    (.candidate_artifact | type == "object" and
      (keys == ["digest", "id", "name"]) and
      (.id | type == "string" and test("^[0-9]+$")) and
      (.digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
      (.name | type == "string" and length > 0))
  ' "$manifest" >/dev/null || fail "candidate evidence has an invalid shape: $manifest"
}

validate_accepted_shape() {
  local manifest="$1"
  require_file "accepted manifest" "$manifest"
  jq -e --arg sha "$SHA_PATTERN" --arg timestamp "$TIMESTAMP_PATTERN" '
    type == "object" and
    (keys == ["accepted_at", "artifact_status", "build_role", "build_timestamp", "builder_sha", "candidate_artifact", "cipher_profile", "evidence_version", "expected_outputs", "key_id", "leptonica_pin_sha", "payload_digest", "release_id", "repository", "source_ci", "source_contract_version", "source_revision", "target_id", "transport_digest", "transport_profile", "workflow_run_attempt", "workflow_run_id", "workflow_run_number"]) and
    .evidence_version == 1 and .artifact_status == "accepted" and
    .source_contract_version == 1 and
    (.release_id | type == "string" and test("^release-v1-[0-9a-f]{64}$")) and
    (.source_revision | type == "string" and test($sha)) and
    (.target_id | type == "string" and test("^target-v1-[0-9a-f]{64}$")) and
    (.build_role == "dev" or .build_role == "prod") and
    .expected_outputs == ["leptonica.wasm", "leptonica.mjs", "build-info.json"] and
    .transport_profile == "envelope-v1" and .cipher_profile == "age-x25519-v1" and
    (.key_id | type == "string" and test("^[A-Za-z0-9._-]+$")) and
    (.payload_digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
    (.transport_digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
    (.build_timestamp | type == "string" and test($timestamp)) and
    (.accepted_at | type == "string" and test($timestamp)) and
    (.workflow_run_id | type == "string" and length > 0) and
    (.workflow_run_number | type == "string" and length > 0) and
    (.workflow_run_attempt | type == "string" and length > 0) and
    (.repository | type == "string" and test("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")) and
    (.builder_sha | type == "string" and test($sha)) and
    (.leptonica_pin_sha | type == "string" and test($sha)) and
    (.candidate_artifact | type == "object" and
      (keys == ["digest", "id", "name"]) and
      (.id | type == "string" and test("^[0-9]+$")) and
      (.digest | type == "string" and test("^sha256:[0-9a-f]{64}$")) and
      (.name | type == "string" and length > 0)) and
    .source_ci == {status: "passed"}
  ' "$manifest" >/dev/null || fail "accepted manifest has an invalid shape: $manifest"
}

validate_identity() {
  local manifest="$1" target_json="$2" contract_version="$3"
  local source_revision="$4" release_id="$5" repository="$6"
  local builder_sha="$7" leptonica_pin_sha="$8" workflow_run_id="$9"
  local workflow_run_number="${10}" workflow_run_attempt="${11}"
  jq -e \
    --argjson target "$target_json" --argjson contract_version "$contract_version" \
    --arg source_revision "$source_revision" \
    --arg release_id "$release_id" --arg repository "$repository" \
    --arg builder_sha "$builder_sha" --arg leptonica_pin_sha "$leptonica_pin_sha" \
    --arg workflow_run_id "$workflow_run_id" --arg workflow_run_number "$workflow_run_number" \
    --arg workflow_run_attempt "$workflow_run_attempt" '
      .source_contract_version == $contract_version and
      .source_revision == $source_revision and
      .release_id == $release_id and .target_id == $target.target_id and
      .build_role == $target.build_role and .expected_outputs == $target.outputs and
      .transport_profile == $target.transport_profile and .repository == $repository and
      .builder_sha == $builder_sha and .leptonica_pin_sha == $leptonica_pin_sha and
      .workflow_run_id == $workflow_run_id and
      .workflow_run_number == $workflow_run_number and
      .workflow_run_attempt == $workflow_run_attempt
    ' "$manifest" >/dev/null || fail "manifest identity does not match the expected release target: $manifest"
}
create_candidate() {
  parse_options "$@"
  assert_known_options output payload-dir source-build-info release-manifest \
    contract-version source-revision release-id target-id \
    build-timestamp workflow-run-id workflow-run-number workflow-run-attempt \
    repository builder-sha leptonica-pin-sha

  local output payload_dir source_build_info release_manifest contract_version
  local source_revision release_id target_id build_timestamp
  local workflow_run_id workflow_run_number workflow_run_attempt repository
  local builder_sha leptonica_pin_sha target_json output_name
  output="$(required_option output)"
  payload_dir="$(required_option payload-dir)"
  source_build_info="$(required_option source-build-info)"
  release_manifest="$(required_option release-manifest)"
  contract_version="$(required_option contract-version)"
  source_revision="$(required_option source-revision)"
  release_id="$(required_option release-id)"
  target_id="$(required_option target-id)"
  build_timestamp="$(required_option build-timestamp)"
  workflow_run_id="$(required_option workflow-run-id)"
  workflow_run_number="$(required_option workflow-run-number)"
  workflow_run_attempt="$(required_option workflow-run-attempt)"
  repository="$(required_option repository)"
  builder_sha="$(required_option builder-sha)"
  leptonica_pin_sha="$(required_option leptonica-pin-sha)"

  require_directory "candidate payload directory" "$payload_dir"
  require_repository "builder repository" "$repository"
  require_sha "builder SHA" "$builder_sha"
  require_sha "leptonica pin SHA" "$leptonica_pin_sha"
  require_timestamp "build timestamp" "$build_timestamp"
  require_target_id "target ID" "$target_id"
  validate_source_manifest "$release_manifest" "$contract_version" "$source_revision" "$release_id"
  target_json="$(manifest_target "$release_manifest" "$target_id")"
  validate_source_build_info "$source_build_info" "$contract_version" "$release_id" "$source_revision" "$target_json"
  [[ "$output" == "$payload_dir/build-info.json" ]] || fail "candidate build-info must be written inside the payload directory"

  jq -S -n \
    --argjson source_contract_version "$contract_version" \
    --arg release_id "$release_id" --arg source_revision "$source_revision" \
    --arg target_id "$target_id" \
    --arg build_role "$(jq -r '.build_role' <<<"$target_json")" \
    --argjson expected_outputs "$(jq -c '.outputs' <<<"$target_json")" \
    --arg transport_profile "$(jq -r '.transport_profile' <<<"$target_json")" \
    --arg build_timestamp "$build_timestamp" --arg workflow_run_id "$workflow_run_id" \
    --arg workflow_run_number "$workflow_run_number" \
    --arg workflow_run_attempt "$workflow_run_attempt" --arg repository "$repository" \
    --arg builder_sha "$builder_sha" --arg leptonica_pin_sha "$leptonica_pin_sha" \
    '{
      evidence_version: 1, artifact_status: "candidate",
      source_contract_version: $source_contract_version,
      source_revision: $source_revision,
      release_id: $release_id, target_id: $target_id, build_role: $build_role,
      expected_outputs: $expected_outputs, transport_profile: $transport_profile,
      build_timestamp: $build_timestamp, workflow_run_id: $workflow_run_id,
      workflow_run_number: $workflow_run_number,
      workflow_run_attempt: $workflow_run_attempt, repository: $repository,
      builder_sha: $builder_sha, leptonica_pin_sha: $leptonica_pin_sha
    }' >"$output"

  while IFS= read -r output_name; do
    if [[ "$output_name" == "build-info.json" ]]; then
      require_file "declared candidate output '$output_name'" "$payload_dir/$output_name"
    else
      require_file "declared candidate output '$output_name'" "$payload_dir/dist/$output_name"
    fi
  done < <(jq -r '.outputs[]' <<<"$target_json")
  validate_candidate_shape "$output"
}

attach_candidate_artifact() {
  parse_options "$@"
  assert_known_options candidate transport-dir output expected-key-id \
    artifact-name artifact-id artifact-digest

  local candidate transport_dir output expected_key_id artifact_name artifact_id
  local artifact_digest envelope_json expected_artifact_name
  candidate="$(required_option candidate)"
  transport_dir="$(required_option transport-dir)"
  output="$(required_option output)"
  expected_key_id="$(required_option expected-key-id)"
  artifact_name="$(required_option artifact-name)"
  artifact_id="$(required_option artifact-id)"
  artifact_digest="$(required_option artifact-digest)"

  validate_candidate_shape "$candidate"
  [[ "$expected_key_id" =~ ^[A-Za-z0-9._-]+$ ]] || fail "transport key ID is invalid"
  [[ "$artifact_id" =~ ^[0-9]+$ ]] || fail "artifact ID is not numeric"
  [[ "$artifact_digest" =~ $ARTIFACT_DIGEST_INPUT_PATTERN ]] || fail "artifact digest is not SHA-256"
  artifact_digest="sha256:${artifact_digest#sha256:}"
  expected_artifact_name="$(candidate_artifact_name \
    "$(jq -r '.workflow_run_id' "$candidate")" \
    "$(jq -r '.workflow_run_attempt' "$candidate")" \
    "$(jq -r '.target_id' "$candidate")")"
  [[ "$artifact_name" == "$expected_artifact_name" ]] || fail "candidate artifact name does not match target identity"

  envelope_json="$(bash "$SCRIPT_DIR/candidate-transport.sh" inspect --transport-dir "$transport_dir")"
  jq -e --argjson envelope "$envelope_json" --arg expected_key_id "$expected_key_id" '
    .release_id == $envelope.release_id and
    .source_revision == $envelope.source_revision and
    .target_id == $envelope.target_id and .build_role == $envelope.build_role and
    .transport_profile == $envelope.transport_profile and
    $envelope.key_id == $expected_key_id
  ' "$candidate" >/dev/null || fail "transport envelope does not match candidate identity"

  mkdir -p "$(dirname "$output")"
  jq -S --argjson envelope "$envelope_json" --arg artifact_name "$artifact_name" \
    --arg artifact_id "$artifact_id" --arg artifact_digest "$artifact_digest" '
      . + {
        cipher_profile: $envelope.cipher_profile, key_id: $envelope.key_id,
        payload_digest: $envelope.payload_digest,
        transport_digest: $envelope.transport_digest,
        candidate_artifact: {name: $artifact_name, id: $artifact_id, digest: $artifact_digest}
      }
    ' "$candidate" >"$output"
  validate_evidence_shape "$output"
}

validate_evidence_set() (
  local release_manifest="$1" evidence_dir="$2" entries expected_count target_id
  require_directory "candidate evidence directory" "$evidence_dir"
  expected_count="$(jq '.targets | length' "$release_manifest")"
  shopt -s nullglob dotglob
  entries=("$evidence_dir"/*)
  [[ "${#entries[@]}" == "$expected_count" ]] || fail "candidate evidence does not match release-set cardinality"
  while IFS= read -r target_id; do
    require_file "candidate evidence for $target_id" "$evidence_dir/$target_id.json"
  done < <(jq -r '.targets[].target_id' "$release_manifest")
)
accept_candidate_set() {
  parse_options "$@"
  assert_known_options release-manifest evidence-dir output-dir accepted-at \
    contract-version source-revision \
    release-id repository builder-sha leptonica-pin-sha workflow-run-id \
    workflow-run-number workflow-run-attempt

  local release_manifest evidence_dir output_dir accepted_at
  local contract_version source_revision release_id repository
  local builder_sha leptonica_pin_sha workflow_run_id workflow_run_number
  local workflow_run_attempt target_json target_id evidence output artifact_name
  release_manifest="$(required_option release-manifest)"
  evidence_dir="$(required_option evidence-dir)"
  output_dir="$(required_option output-dir)"
  accepted_at="$(required_option accepted-at)"
  contract_version="$(required_option contract-version)"
  source_revision="$(required_option source-revision)"
  release_id="$(required_option release-id)"
  repository="$(required_option repository)"
  builder_sha="$(required_option builder-sha)"
  leptonica_pin_sha="$(required_option leptonica-pin-sha)"
  workflow_run_id="$(required_option workflow-run-id)"
  workflow_run_number="$(required_option workflow-run-number)"
  workflow_run_attempt="$(required_option workflow-run-attempt)"

  require_timestamp "acceptance timestamp" "$accepted_at"
  require_repository "builder repository" "$repository"
  require_sha "builder SHA" "$builder_sha"
  require_sha "leptonica pin SHA" "$leptonica_pin_sha"
  validate_source_manifest "$release_manifest" "$contract_version" "$source_revision" "$release_id"
  validate_evidence_set "$release_manifest" "$evidence_dir"

  while IFS= read -r target_json; do
    target_id="$(jq -r '.target_id' <<<"$target_json")"
    evidence="$evidence_dir/$target_id.json"
    output="$output_dir/$target_id/build-info.json"
    artifact_name="$(candidate_artifact_name "$workflow_run_id" "$workflow_run_attempt" "$target_id")"
    validate_evidence_shape "$evidence"
    validate_identity "$evidence" "$target_json" "$contract_version" \
      "$source_revision" "$release_id" "$repository" \
      "$builder_sha" "$leptonica_pin_sha" "$workflow_run_id" \
      "$workflow_run_number" "$workflow_run_attempt"
    [[ "$(jq -r '.candidate_artifact.name' "$evidence")" == "$artifact_name" ]] || fail "candidate artifact name is invalid for $target_id"

    mkdir -p "$(dirname "$output")"
    jq -S --arg accepted_at "$accepted_at" '
      .artifact_status = "accepted" |
      .accepted_at = $accepted_at |
      .source_ci = {status: "passed"}
    ' "$evidence" >"$output"
    validate_accepted_shape "$output"
  done < <(jq -c '.targets[]' "$release_manifest")

  jq -S . "$release_manifest" >"$output_dir/release-set.json"
}

validate_transport_pair() {
  parse_options "$@"
  assert_known_options transport-dir accepted release-manifest target-id \
    contract-version source-revision release-id repository \
    builder-sha checked-out-builder-sha leptonica-pin-sha workflow-run-id \
    workflow-run-number workflow-run-attempt artifact-id artifact-digest

  local transport_dir accepted release_manifest target_id contract_version
  local source_revision release_id repository builder_sha
  local checked_out_builder_sha leptonica_pin_sha workflow_run_id
  local workflow_run_number workflow_run_attempt artifact_id artifact_digest
  local target_json envelope_json artifact_name
  transport_dir="$(required_option transport-dir)"
  accepted="$(required_option accepted)"
  release_manifest="$(required_option release-manifest)"
  target_id="$(required_option target-id)"
  contract_version="$(required_option contract-version)"
  source_revision="$(required_option source-revision)"
  release_id="$(required_option release-id)"
  repository="$(required_option repository)"
  builder_sha="$(required_option builder-sha)"
  checked_out_builder_sha="$(required_option checked-out-builder-sha)"
  leptonica_pin_sha="$(required_option leptonica-pin-sha)"
  workflow_run_id="$(required_option workflow-run-id)"
  workflow_run_number="$(required_option workflow-run-number)"
  workflow_run_attempt="$(required_option workflow-run-attempt)"
  artifact_id="$(required_option artifact-id)"
  artifact_digest="$(required_option artifact-digest)"

  require_sha "checked-out builder SHA" "$checked_out_builder_sha"
  [[ "$checked_out_builder_sha" == "$builder_sha" ]] || fail "checked-out builder revision differs from triggering build"
  [[ "$artifact_id" =~ ^[0-9]+$ ]] || fail "artifact ID is not numeric"
  [[ "$artifact_digest" =~ $ARTIFACT_DIGEST_PATTERN ]] || fail "artifact digest is not SHA-256"
  validate_source_manifest "$release_manifest" "$contract_version" "$source_revision" "$release_id"
  target_json="$(manifest_target "$release_manifest" "$target_id")"
  validate_accepted_shape "$accepted"
  validate_identity "$accepted" "$target_json" "$contract_version" \
    "$source_revision" "$release_id" "$repository" \
    "$builder_sha" "$leptonica_pin_sha" "$workflow_run_id" \
    "$workflow_run_number" "$workflow_run_attempt"
  artifact_name="$(candidate_artifact_name "$workflow_run_id" "$workflow_run_attempt" "$target_id")"
  jq -e --arg artifact_name "$artifact_name" --arg artifact_id "$artifact_id" \
    --arg artifact_digest "$artifact_digest" '
      .candidate_artifact == {name: $artifact_name, id: $artifact_id, digest: $artifact_digest}
    ' "$accepted" >/dev/null || fail "downloaded artifact identity does not match accepted evidence"

  envelope_json="$(bash "$SCRIPT_DIR/candidate-transport.sh" inspect --transport-dir "$transport_dir")"
  jq -e --argjson envelope "$envelope_json" '
    .release_id == $envelope.release_id and
    .source_revision == $envelope.source_revision and
    .target_id == $envelope.target_id and .build_role == $envelope.build_role and
    .transport_profile == $envelope.transport_profile and
    .cipher_profile == $envelope.cipher_profile and .key_id == $envelope.key_id and
    .payload_digest == $envelope.payload_digest and
    .transport_digest == $envelope.transport_digest
  ' "$accepted" >/dev/null || fail "transport metadata does not match accepted evidence"
}
validate_release_pair() {
  parse_options "$@"
  assert_known_options candidate accepted release-manifest target-id \
    contract-version source-revision release-id repository \
    builder-sha checked-out-builder-sha leptonica-pin-sha workflow-run-id \
    workflow-run-number workflow-run-attempt

  local candidate accepted release_manifest target_id contract_version
  local source_revision release_id repository builder_sha
  local checked_out_builder_sha leptonica_pin_sha workflow_run_id
  local workflow_run_number workflow_run_attempt target_json
  local candidate_provenance accepted_provenance
  candidate="$(required_option candidate)"
  accepted="$(required_option accepted)"
  release_manifest="$(required_option release-manifest)"
  target_id="$(required_option target-id)"
  contract_version="$(required_option contract-version)"
  source_revision="$(required_option source-revision)"
  release_id="$(required_option release-id)"
  repository="$(required_option repository)"
  builder_sha="$(required_option builder-sha)"
  checked_out_builder_sha="$(required_option checked-out-builder-sha)"
  leptonica_pin_sha="$(required_option leptonica-pin-sha)"
  workflow_run_id="$(required_option workflow-run-id)"
  workflow_run_number="$(required_option workflow-run-number)"
  workflow_run_attempt="$(required_option workflow-run-attempt)"

  require_sha "checked-out builder SHA" "$checked_out_builder_sha"
  [[ "$checked_out_builder_sha" == "$builder_sha" ]] || fail "checked-out builder revision differs from triggering build"
  validate_source_manifest "$release_manifest" "$contract_version" "$source_revision" "$release_id"
  target_json="$(manifest_target "$release_manifest" "$target_id")"
  validate_candidate_shape "$candidate"
  validate_accepted_shape "$accepted"
  validate_identity "$candidate" "$target_json" "$contract_version" \
    "$source_revision" "$release_id" "$repository" \
    "$builder_sha" "$leptonica_pin_sha" "$workflow_run_id" \
    "$workflow_run_number" "$workflow_run_attempt"
  validate_identity "$accepted" "$target_json" "$contract_version" \
    "$source_revision" "$release_id" "$repository" \
    "$builder_sha" "$leptonica_pin_sha" "$workflow_run_id" \
    "$workflow_run_number" "$workflow_run_attempt"

  candidate_provenance="$(jq -S -c 'del(.artifact_status)' "$candidate")"
  accepted_provenance="$(jq -S -c 'del(.artifact_status, .accepted_at, .source_ci, .cipher_profile, .key_id, .payload_digest, .transport_digest, .candidate_artifact)' "$accepted")"
  [[ "$candidate_provenance" == "$accepted_provenance" ]] || fail "materialized candidate and accepted provenance do not match"
}

validate_source_manifest_command() {
  parse_options "$@"
  assert_known_options manifest contract-version source-revision release-id
  validate_source_manifest "$(required_option manifest)" \
    "$(required_option contract-version)" "$(required_option source-revision)" \
    "$(required_option release-id)"
}

print_release_matrix() {
  parse_options "$@"
  assert_known_options manifest contract-version source-revision release-id
  local manifest contract_version source_revision release_id
  manifest="$(required_option manifest)"
  contract_version="$(required_option contract-version)"
  source_revision="$(required_option source-revision)"
  release_id="$(required_option release-id)"
  validate_source_manifest "$manifest" "$contract_version" "$source_revision" "$release_id"
  jq -c '{include: [.targets[] | {target_id, build_role}]}' "$manifest"
}

main() {
  (($# > 0)) || { usage >&2; exit 1; }
  local command="$1"
  shift
  case "$command" in
    validate-source-manifest) validate_source_manifest_command "$@" ;;
    print-release-matrix) print_release_matrix "$@" ;;
    create-candidate) create_candidate "$@" ;;
    attach-candidate-artifact) attach_candidate_artifact "$@" ;;
    accept-candidate-set) accept_candidate_set "$@" ;;
    validate-transport-pair) validate_transport_pair "$@" ;;
    validate-release-pair) validate_release_pair "$@" ;;
    -h | --help | help) usage ;;
    *) usage >&2; fail "unknown command '$command'" ;;
  esac
}

main "$@"
