output "gateway_id" {
  description = "OCID of the API gateway"
  value       = oci_apigateway_gateway.this.id
}

output "gateway_hostname" {
  description = "Hostname of the API gateway"
  value       = oci_apigateway_gateway.this.hostname
}

output "deployment_id" {
  description = "OCID of the API gateway deployment"
  value       = oci_apigateway_deployment.auth.id
}
