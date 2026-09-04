# A reserved address the DNS record can point at for the life of the project, independent of any Gateway object that happens to be using it.
resource "google_compute_global_address" "gateway" {
  project      = var.project_id
  name         = var.address_name
  address_type = "EXTERNAL"
  description  = "Static frontend address for the external Gateway"
}

# Certificate Manager stores resource references by project number, while a resource ID built from var.project_id carries the project ID. Reading the number lets the certificate below be written in the form the API returns.
data "google_project" "this" {
  project_id = var.project_id
}

# Proves control of the domain through a DNS record, so the certificate can be issued and renewed without depending on live traffic.
resource "google_certificate_manager_dns_authorization" "default" {
  project = var.project_id
  name    = "${var.address_name}-dns-auth"
  domain  = var.domain
}

# Google issues this and renews it before expiry. Nothing to rotate by hand.
resource "google_certificate_manager_certificate" "default" {
  project = var.project_id
  name    = "${var.address_name}-cert"

  managed {
    domains = [var.domain]

    # Not the authorization's own id. That is projects/PROJECT_ID/..., the API stores projects/PROJECT_NUMBER/..., and the whole managed block is immutable, so the difference plans a replacement on every apply forever. Naming the authorization by resource still orders the two correctly.
    dns_authorizations = [
      "projects/${data.google_project.this.number}/locations/global/dnsAuthorizations/${google_certificate_manager_dns_authorization.default.name}",
    ]
  }
}

# A map lets one Gateway serve several certificates, chosen by hostname. The Gateway references the map, not the certificate.
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