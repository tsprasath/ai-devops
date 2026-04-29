output "waf_policy_id" {
  description = "OCID of the WAF policy"
  value       = oci_waf_web_app_firewall_policy.this.id
}

output "waf_id" {
  description = "OCID of the WAF"
  value       = oci_waf_web_app_firewall.this.id
}
