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

variable "subnet_id" {
  description = "OCID of the public subnet for the gateway"
  type        = string
}

variable "auth_backend_url" {
  description = "Backend URL for auth-service (K8s LB IP, e.g. http://10.0.1.100:8080)"
  type        = string
}

variable "allowed_origins" {
  description = "List of allowed CORS origins"
  type        = list(string)
  default     = ["*"]
}
