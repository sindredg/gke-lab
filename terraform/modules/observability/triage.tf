# A notification channel has no send API; it delivers only when a policy
# fires. So a verdict becomes a log entry, the metric counts it, and the
# policy carries its labels into the mail the existing channel sends.
resource "google_logging_metric" "triage_verdict" {
  project = var.project_id
  name    = "triage/verdicts"

  filter = join(" AND ", [
    "logName = \"projects/${var.project_id}/logs/triage-verdict\"",
    "jsonPayload.verdict != \"accepted\"",
  ])

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    labels {
      key         = "verdict"
      value_type  = "STRING"
      description = "contradicts_decision, new, or insufficient_evidence"
    }

    labels {
      key         = "category"
      value_type  = "STRING"
      description = "The finding category, as Security Command Center names it"
    }

    labels {
      key         = "severity"
      value_type  = "STRING"
      description = "The finding severity, as Security Command Center rates it"
    }
  }

  label_extractors = {
    verdict  = "EXTRACT(jsonPayload.verdict)"
    category = "EXTRACT(jsonPayload.finding.category)"
    severity = "EXTRACT(jsonPayload.finding.severity)"
  }
}

# Accepted verdicts are recorded and stay quiet, which the metric filter
# above already enforces. Anything reaching here wants a human.
resource "google_monitoring_alert_policy" "triage_verdict" {
  project      = var.project_id
  display_name = "Security finding needs a decision"
  combiner     = "OR"
  severity     = "WARNING"

  conditions {
    display_name = "A finding was triaged to something other than accepted"

    # No resource.type clause. The type a logs-based metric carries depends
    # on how the entry was written, and no worker has written one yet, so
    # naming it here would be a guess the alert fails silently on. Task 7
    # of Plan C reads the real type off the first verdict and narrows this.
    condition_threshold {
      filter = "metric.type = \"logging.googleapis.com/user/${google_logging_metric.triage_verdict.name}\""

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields = [
          "metric.label.verdict",
          "metric.label.category",
          "metric.label.severity",
        ]
      }

      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  # A verdict is a standing fact, not an outage. Close it so the next one
  # is a fresh notification rather than an update to an open incident.
  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    subject   = "Triage: $${metric.label.verdict} on $${metric.label.category}"
    mime_type = "text/markdown"

    content = <<-EOT
      The triage worker returned `$${metric.label.verdict}` for a `$${metric.label.category}` finding rated `$${metric.label.severity}`.

      The mail carries labels rather than the verdict body, because a logs-based metric bounds label cardinality. The reasoning, the citations and the provenance are in the log entry:

      ```
      gcloud logging read \
        'logName="projects/${var.project_id}/logs/triage-verdict"
         AND jsonPayload.finding.category="$${metric.label.category}"' \
        --limit 5 --format=json
      ```

      What each verdict means:

      - `contradicts_decision`: the finding names something this repository recorded a decision about, and the decision does not hold. Read the cited decision first.
      - `new`: nothing in `.checkov.baseline`, the threat model or `decisions.md` prices this. It needs a decision, not a fix, before anything else.
      - `insufficient_evidence`: the worker refused to rule. Either the model cited a corpus entry that does not resolve, or the input exceeded its budget. This is a worker problem, not a platform one.
    EOT
  }
}
