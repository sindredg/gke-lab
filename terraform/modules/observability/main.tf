# Probes the site from outside; it is the traffic as well as the signal.
resource "google_monitoring_uptime_check_config" "public" {
  project      = var.project_id
  display_name = "${var.domain} healthz"
  timeout      = "10s"
  period       = "60s"

  http_check {
    # /healthz, not /: page content changes, the endpoint is a contract.
    path    = "/healthz"
    port    = 443
    use_ssl = true

    # Also an expiry alarm for the managed certificate.
    validate_ssl = true

    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }

  # A 200 from something that is not this workload is still a failure.
  content_matchers {
    content = "ok"
    matcher = "CONTAINS_STRING"
  }

  monitored_resource {
    type = "uptime_url"

    labels = {
      project_id = var.project_id
      host       = var.domain
    }
  }

  # Google's prober regions, not where the workload runs. Three is the minimum.
  selected_regions = var.uptime_check_regions
}

# An email channel delivers nothing until the address is confirmed once.
resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Platform owner"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

# The one signal that pages. The dashboard is diagnosis, not a page.
resource "google_monitoring_alert_policy" "site_unavailable" {
  project      = var.project_id
  display_name = "${var.domain} is not serving"
  combiner     = "OR"
  severity     = "CRITICAL"

  conditions {
    display_name = "Uptime check failing from more than one checker location"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"monitoring.googleapis.com/uptime_check/check_passed\"",
        "resource.type = \"uptime_url\"",
        "metric.label.check_id = \"${google_monitoring_uptime_check_config.public.uptime_check_id}\"",
      ])

      # COUNT_FALSE per host; a threshold of 1 means at least two locations.
      aggregations {
        alignment_period     = "1200s"
        per_series_aligner   = "ALIGN_NEXT_OLDER"
        cross_series_reducer = "REDUCE_COUNT_FALSE"
        group_by_fields      = ["resource.label.host"]
      }

      comparison      = "COMPARISON_GT"
      threshold_value = 1
      duration        = "60s"

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  # Without this, a self-recovered incident is still open at the next one.
  alert_strategy {
    auto_close = "1800s"
  }

  # An alert without commands moves the diagnosis onto whoever is paged.
  documentation {
    subject   = "${var.domain} is not serving"
    mime_type = "text/markdown"

    content = <<-EOT
      The uptime check for ${var.domain} is failing from more than one of Google's checker locations, so the site is not reachable for users rather than unreachable down one network path. Check in this order, from the workload outwards:

      1. `kubectl get pods -n ${var.namespace} -o wide`:are the Pods Running and Ready? A rollout that failed readiness leaves the previous version serving, so Pods that are all gone means something removed them.
      2. `kubectl get endpointslices -n ${var.namespace} -l kubernetes.io/service-name=nginx`:does the Service still have endpoints? An empty slice is why the load balancer would return 502.
      3. `kubectl describe gateway external -n ${var.namespace}`:is the listener still Programmed and the address unchanged?
      4. Load balancer backend health in the console:are the network endpoint group backends healthy? Unhealthy backends with Ready Pods points at the NetworkPolicy admitting Google's proxy ranges, or at the HealthCheckPolicy target.
      5. `curl -sSi https://${var.domain}/healthz`:what does the edge actually return? A TLS error rather than a status code moves the search to Certificate Manager.
    EOT
  }
}

# The next apply overwrites console edits; export and commit them instead.
resource "google_monitoring_dashboard" "workload_health" {
  project = var.project_id

  dashboard_json = templatefile("${path.module}/dashboards/workload-health.json.tftpl", {
    project_id   = var.project_id
    domain       = var.domain
    cluster_name = var.cluster_name
    namespace    = var.namespace
  })
}
