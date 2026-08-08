#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  publish-github-runner-lambdas.sh <s3_bucket> [--tag <release_tag>] [--prefix <s3_key_prefix>] [--region <aws_region>] [--profile <aws_profile>] [--keep-files]

Description:
  Downloads GitHub runner lambda zip artifacts from the upstream release and uploads
  them to the provided S3 bucket for use by terraform/modules/github_actions_runner.

Default artifacts:
  - webhook.zip
  - runners.zip
  - runner-binaries-syncer.zip

Defaults:
  --tag    v7.10.1
  --prefix github-runner/<tag-without-leading-v>

Examples:
  publish-github-runner-lambdas.sh my-runner-artifacts \
    --tag v7.10.1 \
    --prefix github-runner/7.10.1 \
    --region eu-central-1 \
    --profile personal

  publish-github-runner-lambdas.sh s3://my-runner-artifacts --tag v7.10.1
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

s3_bucket="$1"
shift

tag="v7.10.1"
prefix=""
region=""
profile=""
keep_files="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      if [[ $# -lt 2 ]]; then
        echo "Error: --tag requires a value." >&2
        exit 1
      fi
      tag="$2"
      shift 2
      ;;
    --prefix)
      if [[ $# -lt 2 ]]; then
        echo "Error: --prefix requires a value." >&2
        exit 1
      fi
      prefix="$2"
      shift 2
      ;;
    --region)
      if [[ $# -lt 2 ]]; then
        echo "Error: --region requires a value." >&2
        exit 1
      fi
      region="$2"
      shift 2
      ;;
    --profile)
      if [[ $# -lt 2 ]]; then
        echo "Error: --profile requires a value." >&2
        exit 1
      fi
      profile="$2"
      shift 2
      ;;
    --keep-files)
      keep_files="true"
      shift
      ;;
    *)
      echo "Error: unknown argument '$1'." >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$s3_bucket" ]]; then
  echo "Error: s3_bucket must not be empty." >&2
  exit 1
fi

if [[ "$s3_bucket" == s3://* ]]; then
  s3_bucket="${s3_bucket#s3://}"
fi

if [[ -z "$prefix" ]]; then
  normalized_tag="${tag#v}"
  prefix="github-runner/${normalized_tag}"
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is not installed or not in PATH." >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: aws CLI is not installed or not in PATH." >&2
  exit 1
fi

work_dir="$(mktemp -d)"
cleanup() {
  if [[ "$keep_files" != "true" ]]; then
    rm -rf "$work_dir"
  fi
}
trap cleanup EXIT

artifacts=("webhook" "runners" "runner-binaries-syncer")

aws_args=()
if [[ -n "$region" ]]; then
  aws_args+=(--region "$region")
fi
if [[ -n "$profile" ]]; then
  aws_args+=(--profile "$profile")
fi

for artifact in "${artifacts[@]}"; do
  file_name="${artifact}.zip"
  source_url="https://github.com/github-aws-runners/terraform-aws-github-runner/releases/download/${tag}/${file_name}"
  local_file="${work_dir}/${file_name}"
  s3_key="${prefix}/${file_name}"

  echo "Downloading ${source_url}"
  curl -fL --retry 3 --retry-delay 2 --connect-timeout 10 -o "$local_file" "$source_url"

  echo "Uploading s3://${s3_bucket}/${s3_key}"
  aws s3 cp "$local_file" "s3://${s3_bucket}/${s3_key}" "${aws_args[@]}"
done

echo
echo "Upload complete. Use these values in github_actions_runner:"
echo "  lambda_s3_bucket      = \"${s3_bucket}\""
echo "  webhook_lambda_s3_key = \"${prefix}/webhook.zip\""
echo "  runners_lambda_s3_key = \"${prefix}/runners.zip\""
echo "  syncer_lambda_s3_key  = \"${prefix}/runner-binaries-syncer.zip\""

if [[ "$keep_files" == "true" ]]; then
  echo "Temporary files kept at: ${work_dir}"
fi
