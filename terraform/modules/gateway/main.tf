# A reserved address the DNS record can point at for the project's life.
resource "google_compute_global_address" "gateway" {
  project      = var.project_id
  name         = var.address_name
  address_type = "EXTERNAL"
  description  = "Static frontend address for the external Gateway"
}

# Google's default accepts TLS 1.0 and 1.1, and applies until one is attached.
resource "google_compute_ssl_policy" "default" {
  project         = var.project_id
  name            = "${var.address_name}-ssl-policy"
  profile         = "MODERN"
  min_tls_version = "TLS_1_2"
}

# Phase 12 measured one client reaching the namespace quota; 5 rps per address
# is an eighth of what two replicas serve, and more than a reader generates.
resource "google_compute_security_policy" "default" {
  project = var.project_id
  name    = "${var.address_name}-rate-limit"

  rule {
    action      = "throttle"
    priority    = 1000
    description = "Throttle a single address rather than banning it"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }

    rate_limit_options {
      conform_action = "allow"
      exceed_action  = "deny(429)"
      enforce_on_key = "IP"

      rate_limit_threshold {
        count        = 300
        interval_sec = 60
      }
    }
  }

  # Cloud Armor requires a default rule, and it must be the lowest priority.
  rule {
    action      = "allow"
    priority    = 2147483647
    description = "Default rule, allow everything the rules above did not"

    match {
      versioned_expr = "SRC_IPS_V1"
      config {
        src_ip_ranges = ["*"]
      }
    }
  }
}

# The API stores project numbers, so the certificate is written that way.
data "google_project" "this" {
  project_id = var.project_id
}

# Proves domain control by DNS record, so renewal needs no live traffic.
resource "google_certificate_manager_dns_authorization" "default" {
  project = var.project_id
  name    = "${var.address_name}-dns-auth"
  domain  = var.domain

  # FIXED_RECORD collides with Cloudflare's own TXT at _acme-challenge.
  type = "PER_PROJECT_RECORD"
}

# Google issues this and renews it before expiry. Nothing to rotate by hand.
resource "google_certificate_manager_certificate" "default" {
  project = var.project_id
  name    = "${var.address_name}-cert"

  managed {
    domains = [var.domain]

    # By resource, not id: the id's project form plans a replacement.
    dns_authorizations = [
      "projects/${data.google_project.this.number}/locations/global/dnsAuthorizations/${google_certificate_manager_dns_authorization.default.name}",
    ]
  }
}

# A map lets one Gateway serve several certificates, chosen by hostname.
resource "google_certificate_manager_certificate_map" "default" {
  project = var.project_id
  name    = "${var.address_name}-cert-map"
}

resource "google_certificate_manager_certificate_map_entry" "default" {
  project      = var.project_id
  name         = "${var.address_name}-cert-entry"
  map          = google_certificate_manager_certificate_map.default.name
  certificates = [google_certificate_manager_certificate.default.id]
  hostname     = var.domain
}
