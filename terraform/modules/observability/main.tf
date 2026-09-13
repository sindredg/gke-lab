# Requests the published site from outside Google's network on a fixed period.
# The platform has close to no organic traffic, so an alert built on served requests would evaluate an empty series during an outage and stay silent. This check is both the traffic and the signal.
resource "google_monitoring_uptime_check_config" "public" {
  project      = var.project_id
  display_name = "${var.domain} healthz"
  timeout      = "10s"
  period       = "60s"

  http_check {
    # /healthz instead of /, because the page content changes and the health endpoint is a contract. access_log is off for this path, so a request every minute adds no log ingest.
    path    = "/healthz"
    port    = 443
    use_ssl = true

    # Also makes this an expiry alarm for the managed certificate, which renews unattended.
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

  # Google's prober regions, meaning where the check is requested from. Nothing to do with europe-north1-a, where the workload runs. Three is the minimum the API accepts once the set is named at all, and each named region expands to one or more checker locations, which is what the alert below counts.
  selected_regions = var.uptime_check_regions
}

# Email channels deliver nothing until the address is confirmed at the inbox, so the policy below is not trustworthy until that has happened once.
resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Platform owner"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }
}

# The one signal that pages. Everything on the dashboard is diagnosis and does not need to wake anyone.
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

      # The metric carries one series per checker location, so grouping by host and reducing with COUNT_FALSE counts the locations currently reporting a failed check.
      #
      # The threshold of 1 therefore means at least two locations. One location failing is a network path somewhere on the internet, and paging on it is how an alert teaches its reader to dismiss it. This costs nothing in detection: one zonal cluster behind one global load balancer has no partial-failure mode, so a real outage fails every location within the same check period.
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

  # The default is seven days. Without this, an incident that recovered on its own is still open when the next real one arrives.
  alert_strategy {
    auto_close = "1800s"
  }

  # The difference between an alert and an actionable alert. A notification that says only "uptime check failing" has moved the diagnosis onto whoever is holding the phone.
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

# The console is a good place to build a widget and the wrong place to keep one: the next apply overwrites anything edited there. To keep a console change, export it with `gcloud monitoring dashboards describe <id> --format=json` and commit the result.
resource "google_monitoring_dashboard" "workload_health" {
  project = var.project_id

  dashboard_json = templatefile("${path.module}/dashboards/workload-health.json.tftpl", {
    project_id   = var.project_id
    domain       = var.domain
    cluster_name = var.cluster_name
    namespace    = var.namespace
  })
}
