#!/usr/bin/env bash
set -euo pipefail

# Convenience wrapper for the RunPod S3-compatible endpoint. Credentials are
# read from the environment on every call and are never written to disk.
required=(
  RUNPOD_S3_ACCESS_KEY_ID
  RUNPOD_S3_SECRET_ACCESS_KEY
  RUNPOD_S3_REGION
  RUNPOD_S3_ENDPOINT
)

missing=()
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    missing+=("${name}")
  fi
done

if (( ${#missing[@]} > 0 )); then
  printf 'aws-runpod: missing environment variables: %s\n' "${missing[*]}" >&2
  exit 1
fi

exec env \
  AWS_ACCESS_KEY_ID="${RUNPOD_S3_ACCESS_KEY_ID}" \
  AWS_SECRET_ACCESS_KEY="${RUNPOD_S3_SECRET_ACCESS_KEY}" \
  AWS_DEFAULT_REGION="${RUNPOD_S3_REGION}" \
  aws \
  --region "${RUNPOD_S3_REGION}" \
  --endpoint-url "${RUNPOD_S3_ENDPOINT}" \
  "$@"
