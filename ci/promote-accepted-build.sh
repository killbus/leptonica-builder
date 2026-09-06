#!/usr/bin/env bash

set -euo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CI_DIR
# shellcheck source=ci/network-retry.sh
source "$CI_DIR/network-retry.sh"

declare -A OPTIONS=()

fail() {
  printf 'release promotion: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ci/promote-accepted-build.sh <prepare|publish> [options]

Prepare options:
  --artifact-dir <path>          Materialized candidate payload directory.
  --accepted-manifest <path>     Validated accepted build-info manifest.
  --output-dir <path>            Prepared release repository output directory.
  --build-role <dev|prod>        Operational build role to promote.
  --target-id <target-v1-...>    Opaque release target identity.
  --repository <owner/repo>      Builder repository for production releases.
Publish options:
  --release-dir <path>           Prepared release repository directory.
  --accepted-manifest <path>     Validated accepted build-info manifest.
  --build-role <dev|prod>        Operational build role to promote.
  --target-id <target-v1-...>    Opaque release target identity.
  --repository <owner/repo>      Builder repository for production releases.
  --source-repository <owner/repo>
                                 Required only for dev publication.
  --workflow-id <id>             Triggering build workflow ID.
  --workflow-run-id <id>         Triggering build run ID.
  --workflow-run-attempt <n>     Triggering build run attempt.

Environment for publish:
  GH_TOKEN                       GitHub token used by gh and production push.
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

required_option() {
  local name="$1"
  local value="${OPTIONS[$name]:-}"
  [[ -n "$value" ]] || fail "missing required option '--$name'"
  printf '%s' "$value"
}

assert_known_options() {
  local name
  local allowed=" $* "

  for name in "${!OPTIONS[@]}"; do
    [[ "$allowed" == *" $name "* ]] || fail "unknown option '--$name'"
  done
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1"
}

require_file() {
  [[ -f "$2" ]] || fail "$1 does not exist: $2"
}

require_directory() {
  [[ -d "$2" ]] || fail "$1 does not exist: $2"
}

require_repository() {
  [[ "$2" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "$1 is not an owner/repository name"
}

load_accepted_manifest() {
  BUILD_TIMESTAMP="$(jq -er '.build_timestamp' "$ACCEPTED_MANIFEST")"
  BUILDER_SHA="$(jq -er '.builder_sha' "$ACCEPTED_MANIFEST")"
  SOURCE_REVISION="$(jq -er '.source_revision' "$ACCEPTED_MANIFEST")"
  RELEASE_ID="$(jq -er '.release_id' "$ACCEPTED_MANIFEST")"
  LEPTONICA_PIN_SHA="$(jq -er '.leptonica_pin_sha' "$ACCEPTED_MANIFEST")"

  local manifest_status manifest_target_id manifest_build_role
  manifest_status="$(jq -er '.artifact_status' "$ACCEPTED_MANIFEST")"
  manifest_target_id="$(jq -er '.target_id' "$ACCEPTED_MANIFEST")"
  manifest_build_role="$(jq -er '.build_role' "$ACCEPTED_MANIFEST")"

  [[ "$manifest_status" == "accepted" ]] || fail "manifest is not accepted"
  [[ "$BUILD_ROLE" == "dev" || "$BUILD_ROLE" == "prod" ]] || fail "unsupported build role '$BUILD_ROLE'"
  [[ "$TARGET_ID" =~ ^target-v1-[0-9a-f]{64}$ ]] || fail "target ID is invalid"
  [[ "$RELEASE_ID" =~ ^release-v1-[0-9a-f]{64}$ ]] || fail "release ID is invalid"
  [[ "$SOURCE_REVISION" =~ ^[0-9a-f]{40}$ ]] || fail "source revision is invalid"
  [[ "$manifest_target_id" == "$TARGET_ID" ]] || fail "accepted manifest is for a different target"
  [[ "$manifest_build_role" == "$BUILD_ROLE" ]] || fail "accepted manifest is for a different build role"
}

select_release_identity() {
  local short_commit="${SOURCE_REVISION:0:7}"
  local target_digest="${TARGET_ID#target-v1-}"

  if [[ "$BUILD_ROLE" == "prod" ]]; then
    VERSION="1.0.0-${short_commit}.${target_digest}"
    BRANCH_NAME="release/${TARGET_ID}"
    TITLE="Leptonica WASM ${VERSION}"
  else
    VERSION="1.0.0-${short_commit}-dev"
    BRANCH_NAME="release-dev"
  fi

  TAG_NAME="v${VERSION}"
  [[ -n "$BRANCH_NAME" && "$BRANCH_NAME" != "main" && "$BRANCH_NAME" != *"main"* ]] || \
    fail "refusing to force-push an unsafe release branch"
}

assemble_release_tree() {
  RELEASE_TEMP="$(mktemp -d "$RELEASE_OUTPUT_PARENT/.candidate-release.XXXXXX")"
  require_directory "candidate distribution" "$ARTIFACT_DIR/dist"
  require_file "candidate README" "$ARTIFACT_DIR/README.md"
  require_file "candidate license" "$ARTIFACT_DIR/LICENSE"
  [[ -z "$(find "$ARTIFACT_DIR" -name .git -print -quit)" ]] || \
    fail "candidate payload contains reserved Git metadata"
  [[ -z "$(find "$ARTIFACT_DIR" -name package.json -print -quit)" ]] || \
    fail "candidate payload contains package-manager metadata"

  cp -r "$ARTIFACT_DIR/dist" "$RELEASE_TEMP/"
  cp "$ARTIFACT_DIR/LICENSE" "$RELEASE_TEMP/"
  cp "$ACCEPTED_MANIFEST" "$RELEASE_TEMP/dist/build-info.json"

  if [[ "$BUILD_ROLE" == "prod" ]]; then
    cp README.md "$RELEASE_TEMP/README.md"
  else
    cp "$ARTIFACT_DIR/README.md" "$RELEASE_TEMP/README.md"
  fi
}

create_release_commit() {
  (
    cd "$RELEASE_TEMP"
    git init
    git config user.name "github-actions[bot]"
    git config user.email "github-actions[bot]@users.noreply.github.com"
    git checkout -b "$BRANCH_NAME"
    git add .
    git commit -F- <<EOF
chore: release Leptonica WASM build

Build Role: ${BUILD_ROLE}
Version: ${VERSION}
Release ID: ${RELEASE_ID}
Target ID: ${TARGET_ID}
Builder Commit: ${BUILDER_SHA}
Source Commit: ${SOURCE_REVISION}
Leptonica Pin SHA: ${LEPTONICA_PIN_SHA}
Source CI: passed
Timestamp: ${BUILD_TIMESTAMP}
EOF
  )
}

validate_prepared_release() {
  require_file "prepared build-info" "$RELEASE_DIR/dist/build-info.json"
  cmp -s "$ACCEPTED_MANIFEST" "$RELEASE_DIR/dist/build-info.json" || \
    fail "prepared build-info differs from accepted evidence"
  [[ "$(cd "$RELEASE_DIR" && git branch --show-current)" == "$BRANCH_NAME" ]] || \
    fail "prepared release branch does not match release identity"
  [[ -z "$(cd "$RELEASE_DIR" && git status --porcelain)" ]] || \
    fail "prepared release repository has uncommitted changes"
}

assert_latest_successful_run() {
  local latest_successful_run latest_run_id latest_run_attempt
  [[ "$WORKFLOW_ID" =~ ^[0-9]+$ ]] || fail "workflow ID is invalid"
  [[ "$WORKFLOW_RUN_ID" =~ ^[0-9]+$ ]] || fail "workflow run ID is invalid"
  [[ "$WORKFLOW_RUN_ATTEMPT" =~ ^[0-9]+$ ]] || fail "workflow run attempt is invalid"
  network_retry_capture latest_successful_run 'resolve latest successful build' gh api \
    "repos/${REPOSITORY}/actions/workflows/${WORKFLOW_ID}/runs?branch=main&event=repository_dispatch&status=success&per_page=1" \
    --jq '.workflow_runs[0] | "\(.id) \(.run_attempt)"'
  read -r latest_run_id latest_run_attempt <<<"$latest_successful_run"

  [[ "$latest_run_id" == "$WORKFLOW_RUN_ID" && "$latest_run_attempt" == "$WORKFLOW_RUN_ATTEMPT" ]] || \
    fail "a newer successful dispatched build supersedes this release"
}

select_release_remote() {
  if [[ "$BUILD_ROLE" == "prod" ]]; then
    REMOTE_URL="https://github.com/${REPOSITORY}.git"
  else
    REMOTE_URL="git@github.com:${SOURCE_REPOSITORY}.git"
  fi
}

push_ref_silently() {
  local ref_name="$1"
  git push --force origin "$ref_name" >/dev/null 2>&1
}

push_release_refs() {
  (
    cd "$RELEASE_DIR"
    git remote remove origin >/dev/null 2>&1 || true
    git remote add origin "$REMOTE_URL"
    if [[ "$BUILD_ROLE" == "prod" ]]; then
      local askpass_script
      askpass_script="$(mktemp)"
      trap 'rm -f "$askpass_script"' EXIT
      cat >"$askpass_script" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  *Username*) printf '%s\n' x-access-token ;;
  *Password*) printf '%s\n' "$GH_TOKEN" ;;
  *) exit 1 ;;
esac
EOF
      chmod 700 "$askpass_script"
      export GIT_ASKPASS="$askpass_script"
      export GIT_TERMINAL_PROMPT=0
    fi
    # Git prints the remote URL on both success and failure. Suppress its raw
    # output so the private development remote cannot enter public CI logs;
    # network_retry still emits the safe operation label and exit status.
    network_retry 'push release branch' push_ref_silently "$BRANCH_NAME"
    git tag --force "$TAG_NAME"
    # A force-push is idempotent across an ambiguous transport failure: if the
    # first push reached GitHub but its response was lost, the retry observes
    # the same tag value and succeeds. Delete-then-create cannot provide that
    # property because a successful delete followed by a lost response turns
    # the retry into a permanent missing-ref failure.
    network_retry 'push release tag' push_ref_silently "$TAG_NAME"
  )
}

ensure_production_release_once() {
  local release_inventory="$1"
  local release_notes="$2"
  local release_state

  # This function is one retry attempt. Truncate the response file before each
  # request and parse it only after gh reports success, so partial responses
  # never affect the create-vs-edit decision. Re-listing on every attempt also
  # reconciles an ambiguous successful create after a disconnected response.
  : >"$release_inventory"
  gh api --paginate --slurp \
    "repos/${REPOSITORY}/releases?per_page=100" >"$release_inventory" || return $?
  release_state="$(jq -er --arg tag "$TAG_NAME" \
    'if any(.[][]; .tag_name == $tag) then "present" else "absent" end' \
    "$release_inventory")" || return $?

  if [[ "$release_state" == "present" ]]; then
    gh release edit "$TAG_NAME" \
      --repo "$REPOSITORY" \
      --title "$TITLE" \
      --notes-file "$release_notes"
  else
    gh release create "$TAG_NAME" \
      --repo "$REPOSITORY" \
      --title "$TITLE" \
      --notes-file "$release_notes"
  fi
}

publish_production_release() {
  [[ "$BUILD_ROLE" == "prod" ]] || return 0

  local release_inventory release_notes
  release_inventory="$(mktemp)"
  release_notes="$(mktemp)"

  cat >"$release_notes" <<EOF
# Leptonica WASM Build

This is an automated Leptonica WebAssembly build for an opaque production target.

- **Version**: $VERSION
- **Release ID**: $RELEASE_ID
- **Target ID**: $TARGET_ID
- **Build Role**: $BUILD_ROLE
- **Builder Commit**: $BUILDER_SHA
- **Source Commit**: $SOURCE_REVISION
- **Leptonica Pin SHA**: $LEPTONICA_PIN_SHA
- **Source CI**: passed
- **Timestamp**: $BUILD_TIMESTAMP
EOF

  if network_retry 'ensure GitHub release' ensure_production_release_once \
    "$release_inventory" "$release_notes"; then
    rm -f "$release_inventory"
    rm -f "$release_notes"
  else
    local status=$?
    rm -f "$release_inventory"
    rm -f "$release_notes"
    return "$status"
  fi
}

cleanup_prepare() {
  [[ -z "${RELEASE_TEMP:-}" ]] || rm -rf "$RELEASE_TEMP"
}

prepare_release() {
  parse_options "$@"
  assert_known_options artifact-dir accepted-manifest output-dir build-role target-id \
    repository

  local output_dir output_name
  ARTIFACT_DIR="$(required_option artifact-dir)"
  ACCEPTED_MANIFEST="$(required_option accepted-manifest)"
  output_dir="$(required_option output-dir)"
  BUILD_ROLE="$(required_option build-role)"
  TARGET_ID="$(required_option target-id)"
  REPOSITORY="$(required_option repository)"
  require_directory "candidate payload directory" "$ARTIFACT_DIR"
  require_file "accepted manifest" "$ACCEPTED_MANIFEST"
  require_file "builder README" README.md
  require_repository "builder repository" "$REPOSITORY"
  [[ ! -e "$output_dir" ]] || fail "prepared release output already exists: $output_dir"

  ARTIFACT_DIR="$(cd "$ARTIFACT_DIR" && pwd)"
  ACCEPTED_MANIFEST="$(cd "$(dirname "$ACCEPTED_MANIFEST")" && pwd)/$(basename "$ACCEPTED_MANIFEST")"
  output_name="$(basename "$output_dir")"
  [[ "$output_name" != "." && "$output_name" != ".." ]] || fail "prepared release output name is invalid"
  mkdir -p "$(dirname "$output_dir")"
  RELEASE_OUTPUT_PARENT="$(cd "$(dirname "$output_dir")" && pwd)"
  RELEASE_OUTPUT="$RELEASE_OUTPUT_PARENT/$output_name"

  local command
  for command in git jq; do
    require_command "$command"
  done

  trap cleanup_prepare EXIT
  load_accepted_manifest
  select_release_identity
  assemble_release_tree
  create_release_commit
  mv "$RELEASE_TEMP" "$RELEASE_OUTPUT"
  RELEASE_TEMP=""
}

publish_release() {
  parse_options "$@"
  assert_known_options release-dir accepted-manifest build-role target-id repository \
    source-repository workflow-id workflow-run-id workflow-run-attempt

  RELEASE_DIR="$(required_option release-dir)"
  ACCEPTED_MANIFEST="$(required_option accepted-manifest)"
  BUILD_ROLE="$(required_option build-role)"
  TARGET_ID="$(required_option target-id)"
  REPOSITORY="$(required_option repository)"
  SOURCE_REPOSITORY="${OPTIONS[source-repository]:-}"
  WORKFLOW_ID="$(required_option workflow-id)"
  WORKFLOW_RUN_ID="$(required_option workflow-run-id)"
  WORKFLOW_RUN_ATTEMPT="$(required_option workflow-run-attempt)"

  require_directory "prepared release directory" "$RELEASE_DIR"
  require_file "accepted manifest" "$ACCEPTED_MANIFEST"
  require_repository "builder repository" "$REPOSITORY"
  if [[ "$BUILD_ROLE" == "dev" ]]; then
    SOURCE_REPOSITORY="$(required_option source-repository)"
    require_repository "source repository" "$SOURCE_REPOSITORY"
  else
    [[ -z "$SOURCE_REPOSITORY" ]] || fail "--source-repository is valid only for dev publication"
  fi
  [[ -n "${GH_TOKEN:-}" ]] || fail "GH_TOKEN is required"

  RELEASE_DIR="$(cd "$RELEASE_DIR" && pwd)"
  ACCEPTED_MANIFEST="$(cd "$(dirname "$ACCEPTED_MANIFEST")" && pwd)/$(basename "$ACCEPTED_MANIFEST")"

  local command
  for command in cmp gh git jq; do
    require_command "$command"
  done

  load_accepted_manifest
  select_release_identity
  validate_prepared_release
  select_release_remote
  assert_latest_successful_run
  push_release_refs
  publish_production_release
}

main() {
  (($# >= 1)) || { usage; exit 2; }
  local command="$1"
  shift

  case "$command" in
    prepare) prepare_release "$@" ;;
    publish) publish_release "$@" ;;
    -h|--help|help) usage ;;
    *) fail "unknown command '$command'" ;;
  esac
}

main "$@"
