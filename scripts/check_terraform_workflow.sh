#!/bin/bash
# Fails if the Terraform workflow uses long-lived AWS keys.
set -euo pipefail

file=".github/workflows/terraform.yml"
pattern='AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|aws-access-key-id|aws-secret-access-key'

if grep -nE "$pattern" "$file"; then
  echo "The Terraform workflow must use role-to-assume. Do not add static AWS keys."
  exit 1
fi

if ! grep -q 'role-to-assume:' "$file"; then
  echo "The Terraform workflow must set role-to-assume."
  exit 1
fi
