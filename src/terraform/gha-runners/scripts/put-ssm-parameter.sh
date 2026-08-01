#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  put-ssm-parameter.sh <parameter_name> (--github-app-id <7-digit-id> | --github-app-key-file <pem_file>) [--region <aws_region>] [--profile <aws_profile>]

Description:
  Writes a SecureString SSM parameter using one of two modes:
  - --github-app-id: stores the provided 7-digit GitHub App ID as-is.
  - --github-app-key-file: base64-encodes the file content and stores it.

Examples:
  put-ssm-parameter.sh "/github-action-runners/demo/app/github_app_id" \
    --github-app-id "3368564" \
    --region "eu-central-1" \
    --profile "personal"

  put-ssm-parameter.sh "/github-action-runners/demo/app/github_app_key_base64" \
    --github-app-key-file "$HOME/Downloads/gha-demo-runner-private-key.pem" \
    --region "eu-central-1" \
    --profile "personal"
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 3 ]]; then
  usage
  exit 1
fi

parameter_name="$1"
shift

github_app_id=""
github_app_key_file=""
region=""
profile=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --github-app-id)
      if [[ $# -lt 2 ]]; then
        echo "Error: --github-app-id requires a value." >&2
        exit 1
      fi
      github_app_id="$2"
      shift 2
      ;;
    --github-app-key-file)
      if [[ $# -lt 2 ]]; then
        echo "Error: --github-app-key-file requires a value." >&2
        exit 1
      fi
      github_app_key_file="$2"
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
    *)
      echo "Error: unknown argument '$1'." >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$parameter_name" ]]; then
  echo "Error: parameter_name must not be empty." >&2
  exit 1
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: aws CLI is not installed or not in PATH." >&2
  exit 1
fi

if ! command -v base64 >/dev/null 2>&1; then
  echo "Error: base64 is not installed or not in PATH." >&2
  exit 1
fi

if [[ -n "$github_app_id" && -n "$github_app_key_file" ]]; then
  echo "Error: use either --github-app-id or --github-app-key-file, not both." >&2
  exit 1
fi

if [[ -z "$github_app_id" && -z "$github_app_key_file" ]]; then
  echo "Error: one mode is required: --github-app-id or --github-app-key-file." >&2
  exit 1
fi

value=""

if [[ -n "$github_app_id" ]]; then
  if [[ ! "$github_app_id" =~ ^[0-9]{7}$ ]]; then
    echo "Error: --github-app-id must be a 7-digit numeric string." >&2
    exit 1
  fi
  value="$github_app_id"
fi

if [[ -n "$github_app_key_file" ]]; then
  if [[ ! -f "$github_app_key_file" ]]; then
    echo "Error: file not found: $github_app_key_file" >&2
    exit 1
  fi
  value="$(base64 -w 0 "$github_app_key_file")"
fi

aws_args=(ssm put-parameter --name "$parameter_name" --type SecureString --value "$value" --overwrite)

if [[ -n "$region" ]]; then
  aws_args+=(--region "$region")
fi

if [[ -n "$profile" ]]; then
  aws_args+=(--profile "$profile")
fi

aws "${aws_args[@]}" >/dev/null

echo "Updated SecureString parameter: $parameter_name"
