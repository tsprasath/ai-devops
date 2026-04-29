# Terraform Backend Configuration for OCI Object Storage
#
# OCI Object Storage is S3-compatible, so we use the "s3" backend.
#
# Prerequisites:
#   1. Create an OCI Object Storage bucket (e.g., "diksha-terraform-state")
#   2. Create a Customer Secret Key for S3 compatibility
#   3. Note your namespace: oci os ns get
#
# Uncomment and configure the block below:
#
# terraform {
#   backend "s3" {
#     bucket                      = "diksha-terraform-state"
#     key                         = "dev/terraform.tfstate"
#     region                      = "ap-mumbai-1"
#     endpoint                    = "https://<namespace>.compat.objectstorage.ap-mumbai-1.oraclecloud.com"
#     shared_credentials_file     = "~/.oci/s3_credentials"
#     skip_region_validation      = true
#     skip_credentials_validation = true
#     skip_metadata_api_check     = true
#     force_path_style            = true
#   }
# }
