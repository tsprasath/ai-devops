resource "oci_waf_web_app_firewall_policy" "this" {
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}-${var.environment}-waf-policy"

  # Request access control - block bad user agents
  request_access_control {
    default_action_name = "ALLOW"

    rules {
      name        = "blockBadUserAgents"
      type        = "ACCESS_CONTROL"
      action_name = "BLOCK_403"
      condition   = "i]i]http.request.headers['user-agent'] co 'sqlmap' || i]http.request.headers['user-agent'] co 'nikto' || i]http.request.headers['user-agent'] co 'havij' || i]http.request.headers['user-agent'] co 'nmap'"
      condition_language = "JMESPATH"
    }
  }

  # Rate limiting
  request_rate_limiting {
    rules {
      name        = "rateLimitPerIP"
      type        = "RATE_LIMIT"
      action_name = "BLOCK_429"

      configurations {
        period_in_seconds          = 300
        requests_limit             = 1000
        action_duration_in_seconds = 600
      }
    }
  }

  # Protection rules for XSS, SQLi, RFI
  request_protection {
    rules {
      name        = "SQLiProtection"
      type        = "PROTECTION"
      action_name = "BLOCK_403"

      protection_capabilities {
        key     = "941110"
        version = 1
      }

      protection_capability_settings {
        max_number_of_arguments            = 255
        max_single_argument_length         = 400
        max_total_argument_length          = 64000
      }
    }

    rules {
      name        = "XSSProtection"
      type        = "PROTECTION"
      action_name = "BLOCK_403"

      protection_capabilities {
        key     = "942100"
        version = 1
      }

      protection_capability_settings {
        max_number_of_arguments            = 255
        max_single_argument_length         = 400
        max_total_argument_length          = 64000
      }
    }

    rules {
      name        = "RFIProtection"
      type        = "PROTECTION"
      action_name = "BLOCK_403"

      protection_capabilities {
        key     = "931100"
        version = 1
      }

      protection_capability_settings {
        max_number_of_arguments            = 255
        max_single_argument_length         = 400
        max_total_argument_length          = 64000
      }
    }
  }

  actions {
    name = "ALLOW"
    type = "ALLOW"
  }

  actions {
    name = "BLOCK_403"
    type = "RETURN_HTTP_RESPONSE"
    code = 403
    body {
      type = "STATIC_TEXT"
      text = "Forbidden"
    }
  }

  actions {
    name = "BLOCK_429"
    type = "RETURN_HTTP_RESPONSE"
    code = 429
    body {
      type = "STATIC_TEXT"
      text = "Too Many Requests"
    }
  }
}

resource "oci_waf_web_app_firewall" "this" {
  compartment_id             = var.compartment_id
  display_name               = "${var.project_name}-${var.environment}-waf"
  backend_type               = "LOAD_BALANCER"
  load_balancer_id           = var.load_balancer_id
  web_app_firewall_policy_id = oci_waf_web_app_firewall_policy.this.id
}
