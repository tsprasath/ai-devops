variable "compartment_id" {
  description = "OCI compartment OCID"
  type        = string
}

variable "project_name" {
  description = "Project name for naming and tagging"
  type        = string
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
}

variable "vcn_id" {
  description = "OCID of the VCN"
  type        = string
}

variable "worker_subnet_id" {
  description = "OCID of the worker subnet"
  type        = string
}

variable "pod_subnet_id" {
  description = "OCID of the pod subnet"
  type        = string
}

variable "public_subnet_id" {
  description = "OCID of the public subnet for API endpoint"
  type        = string
}

variable "k8s_version" {
  description = "Kubernetes version for the OKE cluster"
  type        = string
  default     = "v1.28.2"
}

variable "node_shape" {
  description = "Shape for worker nodes"
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "node_ocpus" {
  description = "Number of OCPUs per node (flex shapes)"
  type        = number
  default     = 2
}

variable "node_memory_gb" {
  description = "Memory in GB per node (flex shapes)"
  type        = number
  default     = 32
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "ssh_public_key" {
  description = "SSH public key for node access"
  type        = string
  default     = ""
}
