variable "compartment_id" {
  description = "OCI compartment OCID"
  type        = string
}

variable "project_name" {
  description = "Project name used in repository path"
  type        = string
}

variable "service_name" {
  description = "Service name for the container repository"
  type        = string
  default     = "auth-service"
}

variable "is_public" {
  description = "Whether the repository is public"
  type        = bool
  default     = false
}

variable "is_immutable" {
  description = "Whether image tags are immutable"
  type        = bool
  default     = false
}
