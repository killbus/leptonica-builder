#!/usr/bin/env bash

set -euo pipefail

readonly TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly TRANSPORT="$TEST_DIR/../candidate-transport.sh"
readonly RELEASE_ID="release-v1-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
readonly WRONG_RELEASE_ID="release-v1-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
readonly TARGET_ID="target-v1-1111111111111111111111111111111111111111111111111111111111111111"
readonly WRONG_TARGET_ID="target-v1-2222222222222222222222222222222222222222222222222222222222222222"
readonly SOURCE_REVISION="1111111111111111111111111111111111111111"
readonly BUILD_ROLE="dev"
readonly KEY_ID="builder-key-1"
readonly RECIPIENT="age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

fail() {
  printf 'candidate transport test: %s\n' "$*" >&2
  exit 1
}

assert_fails() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    fail "expected failure: $label"
  fi
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

cat >"$WORK_DIR/failing-age" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$WORK_DIR/failing-age"

mkdir -p "$WORK_DIR/input/nested"
printf 'candidate readme\n' >"$WORK_DIR/input/README.md"
printf 'payload marker\n' >"$WORK_DIR/input/nested/payload.txt"
printf 'test identity\n' >"$WORK_DIR/identity.txt"

prepare_transport() {
  local output_dir="$1"
  AGE_BIN="$WORK_DIR/fake-age" bash "$TRANSPORT" prepare \
    --input-dir "$WORK_DIR/input" \
    --output-dir "$output_dir" \
    --recipient "$RECIPIENT" \
    --key-id "$KEY_ID" \
    --release-id "$RELEASE_ID" \
    --target-id "$TARGET_ID" \
    --source-revision "$SOURCE_REVISION" \
    --build-role "$BUILD_ROLE"
}

materialize_transport() {
  local transport_dir="$1"
  local output_dir="$2"
  local age_bin="${3:-$WORK_DIR/fake-age}"
  local payload_digest transport_digest
  payload_digest="$(jq -r '.payload_digest' "$transport_dir/envelope.json")"
  transport_digest="$(jq -r '.transport_digest' "$transport_dir/envelope.json")"

  AGE_BIN="$age_bin" bash "$TRANSPORT" materialize \
    --transport-dir "$transport_dir" \
    --output-dir "$output_dir" \
    --identity-file "$WORK_DIR/identity.txt" \
    --expected-key-id "$KEY_ID" \
    --expected-payload-digest "$payload_digest" \
    --expected-transport-digest "$transport_digest" \
    --release-id "$RELEASE_ID" \
    --target-id "$TARGET_ID" \
    --source-revision "$SOURCE_REVISION" \
    --build-role "$BUILD_ROLE"
}

prepare_transport "$WORK_DIR/transport"
prepare_transport "$WORK_DIR/transport-repeat"

inspected_envelope="$(bash "$TRANSPORT" inspect --transport-dir "$WORK_DIR/transport")"
[[ "$inspected_envelope" == "$(jq -S -c . "$WORK_DIR/transport/envelope.json")" ]] ||
  fail "inspect did not return canonical envelope metadata"

assert_fails "duplicate prepare option" \
  env AGE_BIN="$WORK_DIR/fake-age" bash "$TRANSPORT" prepare \
    --input-dir "$WORK_DIR/input" \
    --output-dir "$WORK_DIR/duplicate-option" \
    --recipient "$RECIPIENT" \
    --key-id "$KEY_ID" \
    --key-id "$KEY_ID" \
    --release-id "$RELEASE_ID" \
    --target-id "$TARGET_ID" \
    --source-revision "$SOURCE_REVISION" \
    --build-role "$BUILD_ROLE"

assert_fails "malformed release identity" \
  env AGE_BIN="$WORK_DIR/fake-age" bash "$TRANSPORT" prepare \
    --input-dir "$WORK_DIR/input" \
    --output-dir "$WORK_DIR/malformed-release" \
    --recipient "$RECIPIENT" \
    --key-id "$KEY_ID" \
    --release-id "release-invalid" \
    --target-id "$TARGET_ID" \
    --source-revision "$SOURCE_REVISION" \
    --build-role "$BUILD_ROLE"

assert_fails "malformed target identity" \
  env AGE_BIN="$WORK_DIR/fake-age" bash "$TRANSPORT" prepare \
    --input-dir "$WORK_DIR/input" \
    --output-dir "$WORK_DIR/malformed-target" \
    --recipient "$RECIPIENT" \
    --key-id "$KEY_ID" \
    --release-id "$RELEASE_ID" \
    --target-id "target-invalid" \
    --source-revision "$SOURCE_REVISION" \
    --build-role "$BUILD_ROLE"

[[ "$(jq -r '.payload_digest' "$WORK_DIR/transport/envelope.json")" == \
   "$(jq -r '.payload_digest' "$WORK_DIR/transport-repeat/envelope.json")" ]] ||
  fail "candidate archive digest is not deterministic"

[[ -f "$WORK_DIR/transport/envelope.json" ]] || fail "missing envelope.json"
[[ -f "$WORK_DIR/transport/payload.bin" ]] || fail "missing payload.bin"
[[ "$(find "$WORK_DIR/transport" -mindepth 1 -maxdepth 1 -type f | wc -l)" == 2 ]] ||
  fail "transport contains unexpected files"

jq -e \
  --arg release_id "$RELEASE_ID" \
  --arg target_id "$TARGET_ID" \
  --arg source_revision "$SOURCE_REVISION" \
  --arg build_role "$BUILD_ROLE" \
  --arg key_id "$KEY_ID" \
  '.transport_profile == "envelope-v1" and
    .cipher_profile == "age-x25519-v1" and
    .release_id == $release_id and
    .target_id == $target_id and
    .source_revision == $source_revision and
    .build_role == $build_role and
    .key_id == $key_id and
    (.payload_digest | test("^sha256:[0-9a-f]{64}$")) and
    (.transport_digest | test("^sha256:[0-9a-f]{64}$"))' \
  "$WORK_DIR/transport/envelope.json" >/dev/null

materialize_transport "$WORK_DIR/transport" "$WORK_DIR/materialized"
diff -r "$WORK_DIR/input" "$WORK_DIR/materialized" >/dev/null ||
  fail "materialized payload differs from input"

cp -r "$WORK_DIR/transport" "$WORK_DIR/metadata-substitution"
jq --arg release_id "$WRONG_RELEASE_ID" '.release_id = $release_id' \
  "$WORK_DIR/metadata-substitution/envelope.json" \
  >"$WORK_DIR/metadata-substitution/envelope.json.tmp"
mv "$WORK_DIR/metadata-substitution/envelope.json.tmp" \
  "$WORK_DIR/metadata-substitution/envelope.json"
assert_fails "external metadata substitution" \
  materialize_transport "$WORK_DIR/metadata-substitution" "$WORK_DIR/substituted-output"

cp -r "$WORK_DIR/transport" "$WORK_DIR/extra-envelope-field"
jq '.unexpected = true' "$WORK_DIR/extra-envelope-field/envelope.json" \
  >"$WORK_DIR/extra-envelope-field/envelope.json.tmp"
mv "$WORK_DIR/extra-envelope-field/envelope.json.tmp" \
  "$WORK_DIR/extra-envelope-field/envelope.json"
assert_fails "extra envelope field" \
  bash "$TRANSPORT" inspect --transport-dir "$WORK_DIR/extra-envelope-field"

cp -r "$WORK_DIR/transport" "$WORK_DIR/tampered-transport"
printf 'tamper\n' >>"$WORK_DIR/tampered-transport/payload.bin"
assert_fails "transport payload tampering" \
  materialize_transport "$WORK_DIR/tampered-transport" "$WORK_DIR/tampered-output"
[[ ! -e "$WORK_DIR/tampered-output" ]] ||
  fail "failed materialization left a partial plaintext output"

cp -r "$WORK_DIR/transport" "$WORK_DIR/truncated-transport"
head -c 32 "$WORK_DIR/truncated-transport/payload.bin" \
  >"$WORK_DIR/truncated-transport/payload.bin.tmp"
mv "$WORK_DIR/truncated-transport/payload.bin.tmp" \
  "$WORK_DIR/truncated-transport/payload.bin"
assert_fails "truncated transport payload" \
  materialize_transport "$WORK_DIR/truncated-transport" "$WORK_DIR/truncated-output"

cp -r "$WORK_DIR/transport" "$WORK_DIR/inner-substitution"
mkdir -p "$WORK_DIR/inner-substitution-unpacked"
tar -xf "$WORK_DIR/inner-substitution/payload.bin" \
  -C "$WORK_DIR/inner-substitution-unpacked"
jq '.release_id = "release-inner-substituted"' \
  "$WORK_DIR/inner-substitution-unpacked/binding.json" \
  >"$WORK_DIR/inner-substitution-unpacked/binding.json.tmp"
mv "$WORK_DIR/inner-substitution-unpacked/binding.json.tmp" \
  "$WORK_DIR/inner-substitution-unpacked/binding.json"
tar -cf "$WORK_DIR/inner-substitution/payload.bin" \
  -C "$WORK_DIR/inner-substitution-unpacked" binding.json candidate.tar.gz
inner_transport_digest="sha256:$(sha256sum "$WORK_DIR/inner-substitution/payload.bin" | awk '{print $1}')"
jq --arg digest "$inner_transport_digest" '.transport_digest = $digest' \
  "$WORK_DIR/inner-substitution/envelope.json" \
  >"$WORK_DIR/inner-substitution/envelope.json.tmp"
mv "$WORK_DIR/inner-substitution/envelope.json.tmp" \
  "$WORK_DIR/inner-substitution/envelope.json"
assert_fails "inner binding substitution" \
  materialize_transport "$WORK_DIR/inner-substitution" "$WORK_DIR/inner-substitution-output"

cp -r "$WORK_DIR/transport" "$WORK_DIR/extra-inner-field"
mkdir -p "$WORK_DIR/extra-inner-field-unpacked"
tar -xf "$WORK_DIR/extra-inner-field/payload.bin" \
  -C "$WORK_DIR/extra-inner-field-unpacked"
jq '.unexpected = true' "$WORK_DIR/extra-inner-field-unpacked/binding.json" \
  >"$WORK_DIR/extra-inner-field-unpacked/binding.json.tmp"
mv "$WORK_DIR/extra-inner-field-unpacked/binding.json.tmp" \
  "$WORK_DIR/extra-inner-field-unpacked/binding.json"
tar -cf "$WORK_DIR/extra-inner-field/payload.bin" \
  -C "$WORK_DIR/extra-inner-field-unpacked" binding.json candidate.tar.gz
extra_inner_transport_digest="sha256:$(sha256sum "$WORK_DIR/extra-inner-field/payload.bin" | awk '{print $1}')"
jq --arg digest "$extra_inner_transport_digest" '.transport_digest = $digest' \
  "$WORK_DIR/extra-inner-field/envelope.json" \
  >"$WORK_DIR/extra-inner-field/envelope.json.tmp"
mv "$WORK_DIR/extra-inner-field/envelope.json.tmp" \
  "$WORK_DIR/extra-inner-field/envelope.json"
assert_fails "extra inner binding field" \
  materialize_transport "$WORK_DIR/extra-inner-field" "$WORK_DIR/extra-inner-output"

materialization_error="$WORK_DIR/materialization-error.log"
if materialize_transport "$WORK_DIR/transport" "$WORK_DIR/wrong-key-output" \
  "$WORK_DIR/failing-age" > /dev/null 2>"$materialization_error"; then
  fail "materialization command failure unexpectedly succeeded"
fi
grep -F 'unbound variable' "$materialization_error" >/dev/null && \
  fail "materialization command failure exposed an unbound cleanup variable"
[[ ! -e "$WORK_DIR/wrong-key-output" ]] ||
  fail "failed recovery left a partial plaintext output"
materialize_transport "$WORK_DIR/transport" "$WORK_DIR/wrong-key-output"
diff -r "$WORK_DIR/input" "$WORK_DIR/wrong-key-output" >/dev/null ||
  fail "materialization retry changed the candidate payload"

assert_fails "wrong release binding" \
  env AGE_BIN="$WORK_DIR/fake-age" bash "$TRANSPORT" materialize \
    --transport-dir "$WORK_DIR/transport" \
    --output-dir "$WORK_DIR/wrong-release-output" \
    --identity-file "$WORK_DIR/identity.txt" \
    --expected-key-id "$KEY_ID" \
    --expected-payload-digest "$(jq -r '.payload_digest' "$WORK_DIR/transport/envelope.json")" \
    --expected-transport-digest "$(jq -r '.transport_digest' "$WORK_DIR/transport/envelope.json")" \
    --release-id "$WRONG_RELEASE_ID" \
    --target-id "$TARGET_ID" \
    --source-revision "$SOURCE_REVISION" \
    --build-role "$BUILD_ROLE"

assert_fails "wrong target binding" \
  env AGE_BIN="$WORK_DIR/fake-age" bash "$TRANSPORT" materialize \
    --transport-dir "$WORK_DIR/transport" \
    --output-dir "$WORK_DIR/wrong-target-output" \
    --identity-file "$WORK_DIR/identity.txt" \
    --expected-key-id "$KEY_ID" \
    --expected-payload-digest "$(jq -r '.payload_digest' "$WORK_DIR/transport/envelope.json")" \
    --expected-transport-digest "$(jq -r '.transport_digest' "$WORK_DIR/transport/envelope.json")" \
    --release-id "$RELEASE_ID" \
    --target-id "$WRONG_TARGET_ID" \
    --source-revision "$SOURCE_REVISION" \
    --build-role "$BUILD_ROLE"

assert_fails "wrong role binding" \
  env AGE_BIN="$WORK_DIR/fake-age" bash "$TRANSPORT" materialize \
    --transport-dir "$WORK_DIR/transport" \
    --output-dir "$WORK_DIR/wrong-role-output" \
    --identity-file "$WORK_DIR/identity.txt" \
    --expected-key-id "$KEY_ID" \
    --expected-payload-digest "$(jq -r '.payload_digest' "$WORK_DIR/transport/envelope.json")" \
    --expected-transport-digest "$(jq -r '.transport_digest' "$WORK_DIR/transport/envelope.json")" \
    --release-id "$RELEASE_ID" \
    --target-id "$TARGET_ID" \
    --source-revision "$SOURCE_REVISION" \
    --build-role prod

if command -v age >/dev/null 2>&1 && command -v age-keygen >/dev/null 2>&1; then
  age-keygen -o "$WORK_DIR/actual-identity.txt" >/dev/null 2>&1
  actual_recipient="$(age-keygen -y "$WORK_DIR/actual-identity.txt")"
  age-keygen -o "$WORK_DIR/wrong-identity.txt" >/dev/null 2>&1

  bash "$TRANSPORT" prepare \
    --input-dir "$WORK_DIR/input" \
    --output-dir "$WORK_DIR/actual-transport" \
    --recipient "$actual_recipient" \
    --key-id "$KEY_ID" \
    --release-id "$RELEASE_ID" \
    --target-id "$TARGET_ID" \
    --source-revision "$SOURCE_REVISION" \
    --build-role "$BUILD_ROLE"

  if grep -aF 'payload marker' "$WORK_DIR/actual-transport/payload.bin" >/dev/null; then
    fail "actual protected payload contains readable candidate content"
  fi

  actual_payload_digest="$(jq -r '.payload_digest' "$WORK_DIR/actual-transport/envelope.json")"
  actual_transport_digest="$(jq -r '.transport_digest' "$WORK_DIR/actual-transport/envelope.json")"
  bash "$TRANSPORT" materialize \
    --transport-dir "$WORK_DIR/actual-transport" \
    --output-dir "$WORK_DIR/actual-materialized" \
    --identity-file "$WORK_DIR/actual-identity.txt" \
    --expected-key-id "$KEY_ID" \
    --expected-payload-digest "$actual_payload_digest" \
    --expected-transport-digest "$actual_transport_digest" \
    --release-id "$RELEASE_ID" \
    --target-id "$TARGET_ID" \
    --source-revision "$SOURCE_REVISION" \
    --build-role "$BUILD_ROLE"
  diff -r "$WORK_DIR/input" "$WORK_DIR/actual-materialized" >/dev/null ||
    fail "actual age round trip changed the candidate payload"

  assert_fails "wrong age identity" \
    bash "$TRANSPORT" materialize \
    --transport-dir "$WORK_DIR/actual-transport" \
    --output-dir "$WORK_DIR/wrong-identity-output" \
    --identity-file "$WORK_DIR/wrong-identity.txt" \
    --expected-key-id "$KEY_ID" \
    --expected-payload-digest "$actual_payload_digest" \
    --expected-transport-digest "$actual_transport_digest" \
    --release-id "$RELEASE_ID" \
    --target-id "$TARGET_ID" \
    --source-revision "$SOURCE_REVISION" \
    --build-role "$BUILD_ROLE"
fi

printf 'candidate transport tests passed\n'
