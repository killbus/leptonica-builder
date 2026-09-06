#!/usr/bin/env bash

set -euo pipefail

readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CONTRACT="$TEST_DIR/../build-info-contract.sh"
readonly TRANSPORT="$TEST_DIR/../candidate-transport.sh"
readonly CONTRACT_VERSION="1"
readonly BUILDER_SHA="1111111111111111111111111111111111111111"
readonly SOURCE_REVISION="2222222222222222222222222222222222222222"
readonly LEPTONICA_PIN_SHA="3333333333333333333333333333333333333333"
readonly RELEASE_ID="release-v1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
readonly DEV_TARGET="target-v1-1111111111111111111111111111111111111111111111111111111111111111"
readonly PROD_TARGET_A="target-v1-2222222222222222222222222222222222222222222222222222222222222222"
readonly PROD_TARGET_B="target-v1-3333333333333333333333333333333333333333333333333333333333333333"
readonly RUN_ID="12345"
readonly RUN_NUMBER="67"
readonly RUN_ATTEMPT="2"
readonly PRIVATE_SOURCE_SENTINEL="example/leptonica-source"
readonly REPOSITORY="example/leptonica-builder"
readonly BUILD_TIMESTAMP="2026-07-14T01:02:03Z"
readonly ACCEPTED_AT="2026-07-14T02:03:04Z"
readonly KEY_ID="builder-key-1"
readonly RECIPIENT="age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"
readonly ARTIFACT_DIGEST="sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
readonly BARE_ARTIFACT_DIGEST="${ARTIFACT_DIGEST#sha256:}"

# Native Windows jq writes CRLF under Git Bash. Normalize it so shell values
# match the Linux runner contract exactly.
readonly REAL_JQ="$(command -v jq)"
jq() {
  "$REAL_JQ" "$@" | tr -d '\r'
}
export REAL_JQ
export -f jq
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fail() {
  printf 'build-info contract test: %s\n' "$*" >&2
  exit 1
}

assert_fails() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "expected failure: $label"
  fi
}

contract() {
  bash "$CONTRACT" "$@"
}

role_for_target() {
  case "$1" in
    "$DEV_TARGET") printf 'dev' ;;
    "$PROD_TARGET_A"|"$PROD_TARGET_B") printf 'prod' ;;
    *) fail "unknown test target: $1" ;;
  esac
}

artifact_id_for_target() {
  case "$1" in
    "$DEV_TARGET") printf '1001' ;;
    "$PROD_TARGET_A") printf '1002' ;;
    "$PROD_TARGET_B") printf '1003' ;;
    *) fail "unknown test target: $1" ;;
  esac
}

cat >"$WORK_DIR/fake-age" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=''
input=''
while (($#)); do
  case "$1" in
    -r|-i) shift 2 ;;
    -d) shift ;;
    -o) output="$2"; shift 2 ;;
    -*) exit 2 ;;
    *) input="$1"; shift ;;
  esac
done
[[ -n "$output" && -n "$input" ]]
cp "$input" "$output"
EOF
chmod +x "$WORK_DIR/fake-age"
printf 'test identity\n' >"$WORK_DIR/identity.txt"

cat >"$WORK_DIR/release-set.json" <<EOF
{
  "schema_version": 1,
  "release_id": "$RELEASE_ID",
  "source_revision": "$SOURCE_REVISION",
  "targets": [
    {
      "target_id": "$DEV_TARGET",
      "build_role": "dev",
      "outputs": ["leptonica.wasm", "leptonica.mjs", "build-info.json"],
      "transport_profile": "envelope-v1"
    },
    {
      "target_id": "$PROD_TARGET_A",
      "build_role": "prod",
      "outputs": ["leptonica.wasm", "leptonica.mjs", "build-info.json"],
      "transport_profile": "envelope-v1"
    },
    {
      "target_id": "$PROD_TARGET_B",
      "build_role": "prod",
      "outputs": ["leptonica.wasm", "leptonica.mjs", "build-info.json"],
      "transport_profile": "envelope-v1"
    }
  ]
}
EOF

common_identity_args=(
  --contract-version "$CONTRACT_VERSION"
  --source-revision "$SOURCE_REVISION"
  --release-id "$RELEASE_ID"
  --repository "$REPOSITORY"
  --builder-sha "$BUILDER_SHA"
  --leptonica-pin-sha "$LEPTONICA_PIN_SHA"
  --workflow-run-id "$RUN_ID"
  --workflow-run-number "$RUN_NUMBER"
  --workflow-run-attempt "$RUN_ATTEMPT"
)

# Candidate evidence stays at the payload root; declared package files live under dist/.
create_target_evidence() {
  local target_id="$1"
  local role artifact_id payload_dir candidate transport_dir artifact_name
  role="$(role_for_target "$target_id")"
  artifact_id="$(artifact_id_for_target "$target_id")"
  payload_dir="$WORK_DIR/payloads/$target_id"
  candidate="$WORK_DIR/candidates/$target_id.json"
  transport_dir="$WORK_DIR/transports/$target_id"
  artifact_name="candidate-$RUN_ID-$RUN_ATTEMPT-$target_id"

  mkdir -p "$payload_dir/dist" "$(dirname "$candidate")" "$WORK_DIR/evidence"
  printf 'wasm for %s\n' "$target_id" >"$payload_dir/dist/leptonica.wasm"
  printf 'esm for %s\n' "$target_id" >"$payload_dir/dist/leptonica.mjs"
  jq -S -n \
    --argjson schema_version "$CONTRACT_VERSION" \
    --arg release_id "$RELEASE_ID" \
    --arg source_revision "$SOURCE_REVISION" \
    --arg target_id "$target_id" \
    --arg build_role "$role" \
    '{schema_version: $schema_version, release_id: $release_id,
      source_revision: $source_revision, target_id: $target_id,
      build_role: $build_role, transport_profile: "envelope-v1"}' \
    >"$payload_dir/build-info.json"

  contract create-candidate \
    --output "$payload_dir/build-info.json" \
    --payload-dir "$payload_dir" \
    --source-build-info "$payload_dir/build-info.json" \
    --release-manifest "$WORK_DIR/release-set.json" \
    --target-id "$target_id" \
    --build-timestamp "$BUILD_TIMESTAMP" \
    "${common_identity_args[@]}"
  cp "$payload_dir/build-info.json" "$candidate"

  AGE_BIN="$WORK_DIR/fake-age" bash "$TRANSPORT" prepare \
    --input-dir "$payload_dir" \
    --output-dir "$transport_dir" \
    --recipient "$RECIPIENT" \
    --key-id "$KEY_ID" \
    --release-id "$RELEASE_ID" \
    --target-id "$target_id" \
    --source-revision "$SOURCE_REVISION" \
    --build-role "$role"

  contract attach-candidate-artifact \
    --candidate "$candidate" \
    --transport-dir "$transport_dir" \
    --output "$WORK_DIR/evidence/$target_id.json" \
    --expected-key-id "$KEY_ID" \
    --artifact-name "$artifact_name" \
    --artifact-id "$artifact_id" \
    --artifact-digest "$BARE_ARTIFACT_DIGEST"

  [[ "$(jq -r '.candidate_artifact.digest' "$WORK_DIR/evidence/$target_id.json")" == \
     "$ARTIFACT_DIGEST" ]] || fail "bare artifact digest was not canonicalized"
}

contract validate-source-manifest \
  --manifest "$WORK_DIR/release-set.json" \
  --contract-version "$CONTRACT_VERSION" \
  --source-revision "$SOURCE_REVISION" \
  --release-id "$RELEASE_ID"

expected_matrix="$(jq -c '{include: [.targets[] | {target_id, build_role}]}' "$WORK_DIR/release-set.json")"
actual_matrix="$(contract print-release-matrix \
  --manifest "$WORK_DIR/release-set.json" \
  --contract-version "$CONTRACT_VERSION" \
  --source-revision "$SOURCE_REVISION" \
  --release-id "$RELEASE_ID")"
[[ "$actual_matrix" == "$expected_matrix" ]] || fail "release matrix differs from manifest targets"

for target_id in "$DEV_TARGET" "$PROD_TARGET_A" "$PROD_TARGET_B"; do
  create_target_evidence "$target_id"
done

contract accept-candidate-set \
  --release-manifest "$WORK_DIR/release-set.json" \
  --evidence-dir "$WORK_DIR/evidence" \
  --output-dir "$WORK_DIR/accepted" \
  --accepted-at "$ACCEPTED_AT" \
  "${common_identity_args[@]}"

for public_file in "$WORK_DIR/candidates"/*.json "$WORK_DIR/evidence"/*.json "$WORK_DIR/accepted"/*/build-info.json; do
  ! grep -F "$PRIVATE_SOURCE_SENTINEL" "$public_file" >/dev/null ||
    fail "private source repository leaked into $public_file"
done

[[ "$(jq -S -c . "$WORK_DIR/release-set.json")" == \
   "$(jq -S -c . "$WORK_DIR/accepted/release-set.json")" ]] ||
  fail "accepted release set differs from source manifest"

for target_id in "$DEV_TARGET" "$PROD_TARGET_A" "$PROD_TARGET_B"; do
  role="$(role_for_target "$target_id")"
  artifact_id="$(artifact_id_for_target "$target_id")"
  accepted="$WORK_DIR/accepted/$target_id/build-info.json"
  transport="$WORK_DIR/transports/$target_id"
  materialized="$WORK_DIR/materialized/$target_id"

  contract validate-transport-pair \
    --transport-dir "$transport" \
    --accepted "$accepted" \
    --release-manifest "$WORK_DIR/release-set.json" \
    --target-id "$target_id" \
    --checked-out-builder-sha "$BUILDER_SHA" \
    --artifact-id "$artifact_id" \
    --artifact-digest "$ARTIFACT_DIGEST" \
    "${common_identity_args[@]}"

  AGE_BIN="$WORK_DIR/fake-age" bash "$TRANSPORT" materialize \
    --transport-dir "$transport" \
    --output-dir "$materialized" \
    --identity-file "$WORK_DIR/identity.txt" \
    --expected-key-id "$KEY_ID" \
    --expected-payload-digest "$(jq -r '.payload_digest' "$accepted")" \
    --expected-transport-digest "$(jq -r '.transport_digest' "$accepted")" \
    --release-id "$RELEASE_ID" \
    --target-id "$target_id" \
    --source-revision "$SOURCE_REVISION" \
    --build-role "$role"

  contract validate-release-pair \
    --candidate "$materialized/build-info.json" \
    --accepted "$accepted" \
    --release-manifest "$WORK_DIR/release-set.json" \
    --target-id "$target_id" \
    --checked-out-builder-sha "$BUILDER_SHA" \
    "${common_identity_args[@]}"

  jq -e '
    .artifact_status == "accepted" and
    (has("build_type") or has("product_lock") or has("build_variant") or
      has("domain") or has("customer") or has("target_seed") | not)
  ' "$accepted" >/dev/null || fail "accepted evidence contains legacy or private fields"
done

jq '.source_repository = "example/leptonica-source"' \
  "$WORK_DIR/accepted/$DEV_TARGET/build-info.json" >"$WORK_DIR/private-source-accepted.json"
assert_fails "private source repository in accepted evidence" \
  contract validate-release-pair \
    --candidate "$WORK_DIR/materialized/$DEV_TARGET/build-info.json" \
    --accepted "$WORK_DIR/private-source-accepted.json" \
    --release-manifest "$WORK_DIR/release-set.json" \
    --target-id "$DEV_TARGET" \
    --checked-out-builder-sha "$BUILDER_SHA" \
    "${common_identity_args[@]}"

cp "$WORK_DIR/release-set.json" "$WORK_DIR/extra-field-release-set.json"
jq '.unexpected = true' "$WORK_DIR/extra-field-release-set.json" >"$WORK_DIR/tmp.json"
mv "$WORK_DIR/tmp.json" "$WORK_DIR/extra-field-release-set.json"
assert_fails "extra source manifest field" \
  contract validate-source-manifest \
    --manifest "$WORK_DIR/extra-field-release-set.json" \
    --contract-version "$CONTRACT_VERSION" \
    --source-revision "$SOURCE_REVISION" \
    --release-id "$RELEASE_ID"

jq '.targets |= reverse' "$WORK_DIR/release-set.json" >"$WORK_DIR/unsorted-release-set.json"
assert_fails "unsorted source targets" \
  contract validate-source-manifest \
    --manifest "$WORK_DIR/unsorted-release-set.json" \
    --contract-version "$CONTRACT_VERSION" \
    --source-revision "$SOURCE_REVISION" \
    --release-id "$RELEASE_ID"

jq '.targets |= map(.build_role = "prod")' "$WORK_DIR/release-set.json" \
  >"$WORK_DIR/no-dev-release-set.json"
assert_fails "missing dev target" \
  contract validate-source-manifest \
    --manifest "$WORK_DIR/no-dev-release-set.json" \
    --contract-version "$CONTRACT_VERSION" \
    --source-revision "$SOURCE_REVISION" \
    --release-id "$RELEASE_ID"

jq '.targets[0].outputs = ["leptonica.wasm"]' "$WORK_DIR/release-set.json" \
  >"$WORK_DIR/wrong-outputs-release-set.json"
assert_fails "wrong expected outputs" \
  contract validate-source-manifest \
    --manifest "$WORK_DIR/wrong-outputs-release-set.json" \
    --contract-version "$CONTRACT_VERSION" \
    --source-revision "$SOURCE_REVISION" \
    --release-id "$RELEASE_ID"

assert_fails "duplicate contract option" \
  contract validate-source-manifest \
    --manifest "$WORK_DIR/release-set.json" \
    --manifest "$WORK_DIR/release-set.json" \
    --contract-version "$CONTRACT_VERSION" \
    --source-revision "$SOURCE_REVISION" \
    --release-id "$RELEASE_ID"

mkdir -p "$WORK_DIR/missing-evidence"
cp "$WORK_DIR/evidence/$DEV_TARGET.json" "$WORK_DIR/missing-evidence/"
cp "$WORK_DIR/evidence/$PROD_TARGET_A.json" "$WORK_DIR/missing-evidence/"
assert_fails "incomplete evidence set" \
  contract accept-candidate-set \
    --release-manifest "$WORK_DIR/release-set.json" \
    --evidence-dir "$WORK_DIR/missing-evidence" \
    --output-dir "$WORK_DIR/missing-accepted" \
    --accepted-at "$ACCEPTED_AT" \
    "${common_identity_args[@]}"

cp -r "$WORK_DIR/evidence" "$WORK_DIR/extra-evidence"
cp "$WORK_DIR/evidence/$DEV_TARGET.json" "$WORK_DIR/extra-evidence/unexpected.json"
assert_fails "unexpected evidence file" \
  contract accept-candidate-set \
    --release-manifest "$WORK_DIR/release-set.json" \
    --evidence-dir "$WORK_DIR/extra-evidence" \
    --output-dir "$WORK_DIR/extra-accepted" \
    --accepted-at "$ACCEPTED_AT" \
    "${common_identity_args[@]}"

jq '.candidate_artifact.id = "9999"' \
  "$WORK_DIR/accepted/$DEV_TARGET/build-info.json" >"$WORK_DIR/wrong-artifact.json"
assert_fails "hosting artifact identity mismatch" \
  contract validate-transport-pair \
    --transport-dir "$WORK_DIR/transports/$DEV_TARGET" \
    --accepted "$WORK_DIR/wrong-artifact.json" \
    --release-manifest "$WORK_DIR/release-set.json" \
    --target-id "$DEV_TARGET" \
    --checked-out-builder-sha "$BUILDER_SHA" \
    --artifact-id "1001" \
    --artifact-digest "$ARTIFACT_DIGEST" \
    "${common_identity_args[@]}"

cp -r "$WORK_DIR/transports/$DEV_TARGET" "$WORK_DIR/wrong-role-transport"
jq '.build_role = "prod"' "$WORK_DIR/wrong-role-transport/envelope.json" \
  >"$WORK_DIR/tmp.json"
mv "$WORK_DIR/tmp.json" "$WORK_DIR/wrong-role-transport/envelope.json"
assert_fails "transport role mismatch" \
  contract validate-transport-pair \
    --transport-dir "$WORK_DIR/wrong-role-transport" \
    --accepted "$WORK_DIR/accepted/$DEV_TARGET/build-info.json" \
    --release-manifest "$WORK_DIR/release-set.json" \
    --target-id "$DEV_TARGET" \
    --checked-out-builder-sha "$BUILDER_SHA" \
    --artifact-id "1001" \
    --artifact-digest "$ARTIFACT_DIGEST" \
    "${common_identity_args[@]}"

jq '.source_revision = "4444444444444444444444444444444444444444"' \
  "$WORK_DIR/materialized/$DEV_TARGET/build-info.json" >"$WORK_DIR/tampered-candidate.json"
assert_fails "materialized provenance mismatch" \
  contract validate-release-pair \
    --candidate "$WORK_DIR/tampered-candidate.json" \
    --accepted "$WORK_DIR/accepted/$DEV_TARGET/build-info.json" \
    --release-manifest "$WORK_DIR/release-set.json" \
    --target-id "$DEV_TARGET" \
    --checked-out-builder-sha "$BUILDER_SHA" \
    "${common_identity_args[@]}"

printf 'build-info contract tests passed\n'
