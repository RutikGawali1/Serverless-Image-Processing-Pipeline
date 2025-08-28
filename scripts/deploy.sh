#!/bin/bash

set -e  # Exit on error

echo "=== Free Tier Image Processing Pipeline Deployment ==="
echo "This will deploy resources optimized for AWS Free Tier"

# Build the Lambda function package
echo "Building Lambda function..."
cd src/image-processor
chmod +x build.sh
./build.sh
cd ../../

# Initialize Terraform
echo "Initializing Terraform..."
cd infrastructure
terraform init

# Apply Terraform configuration
echo "Deploying infrastructure (this may take a few minutes)..."
terraform apply -auto-approve

echo ""
echo "=== Deployment Complete ==="
echo "Check the outputs above for next steps and important information."
echo "Remember to clean up with 'terraform destroy' when you're done testing."