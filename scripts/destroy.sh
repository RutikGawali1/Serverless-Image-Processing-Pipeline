#!/bin/bash

set -e  # Exit on error

echo "=== Cleaning Up Free Tier Resources ==="
echo "This will destroy all resources created by Terraform"

cd infrastructure
terraform destroy -auto-approve

echo ""
echo "=== Cleanup Complete ==="
echo "All resources have been destroyed to avoid unnecessary charges."