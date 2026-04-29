resource "oci_apigateway_gateway" "this" {
  compartment_id = var.compartment_id
  display_name   = "${var.project_name}-${var.environment}-gateway"
  endpoint_type  = "PUBLIC"
  subnet_id      = var.subnet_id
}

resource "oci_apigateway_deployment" "auth" {
  compartment_id = var.compartment_id
  gateway_id     = oci_apigateway_gateway.this.id
  display_name   = "${var.project_name}-${var.environment}-auth-deployment"
  path_prefix    = "/api/v1/auth"

  specification {
    request_policies {
      rate_limiting {
        rate_in_requests_per_second = 100
        rate_key                    = "CLIENT_IP"
      }

      cors {
        allowed_origins              = var.allowed_origins
        allowed_methods              = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
        allowed_headers              = ["Content-Type", "Authorization"]
        is_allow_credentials_enabled = true
        max_age_in_seconds           = 3600
      }
    }

    routes {
      path    = "/{path*}"
      methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]

      backend {
        type = "HTTP_BACKEND"
        url  = "${var.auth_backend_url}/api/v1/auth/$${request.path[path]}"
      }

      request_policies {
        authorization {
          type = "AUTHENTICATION_ONLY"
        }
      }
    }

    routes {
      path    = "/health"
      methods = ["GET"]

      backend {
        type = "HTTP_BACKEND"
        url  = "${var.auth_backend_url}/api/v1/auth/health"
      }

      request_policies {
        authorization {
          type = "ANONYMOUS"
        }
      }
    }

    authentication_policies {
      default_authentication_policy {
        type                        = "JWT_AUTHENTICATION"
        token_header                = "Authorization"
        token_auth_scheme           = "Bearer"
        is_anonymous_access_allowed = true

        verify_claims {
          key   = "iss"
          values = var.allowed_origins
        }
      }
    }
  }
}
