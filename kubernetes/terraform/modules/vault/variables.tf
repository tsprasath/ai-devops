variable "compartment_id" {
  description = "OCI compartment OCID"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "vault_type" {
  description = "Type of vault (DEFAULT or VIRTUAL_PRIVATE)"
  type        = string
  default     = "DEFAULT"
}
