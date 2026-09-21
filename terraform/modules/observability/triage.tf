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

    # Cloud Monitoring rejects a threshold filter with no resource.type,
    # so this cannot be left open: creating the policy without it fails
    # with "must specify a restriction on resource.type". k8s_container
    # is therefore a contract rather than an observation. The worker runs
    # as a Pod and must set that monitored resource explicitly rather than
    # relying on client-library detection, because a different type here
    # matches nothing and the alert then fails silently instead of loudly.
    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"logging.googleapis.com/user/${google_logging_metric.triage_verdict.name}\"",
        "resource.type = \"k8s_container\"",
      ])

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

# A finding that fails five deliveries is parked on the dead letter topic
# with its body intact. Parked is not lost, but nothing re-drives that
# subscription, so without this a ledger or model outage of about a
# minute leaves findings nobody triages and nobody hears about. Five
# attempts took 68 seconds when the ledger write failure was drilled.
#
# Counted on the source subscription as each message is forwarded, so the
# messages already parked do not hold the alert open.
resource "google_monitoring_alert_policy" "triage_dead_letter" {
  project      = var.project_id
  display_name = "Security finding was dead-lettered"
  combiner     = "OR"
  severity     = "ERROR"

  conditions {
    display_name = "A finding exhausted its deliveries on the triage subscription"

    condition_threshold {
      filter = join(" AND ", [
        "metric.type = \"pubsub.googleapis.com/subscription/dead_letter_message_count\"",
        "resource.type = \"pubsub_subscription\"",
        "resource.label.subscription_id = \"${var.triage_subscription}\"",
      ])

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
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

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    subject   = "Triage: a finding was dead-lettered"
    mime_type = "text/markdown"

    content = <<-EOT
      A finding failed five deliveries to the triage worker and was moved to the dead letter topic. It has not been triaged, and nothing will retry it.

      Read the worker's errors first. A ledger or model failure logs `triage failed, leaving the message unacknowledged` once per attempt:

      ```
      kubectl logs -n agents deploy/triage-worker --since=1h | grep "triage failed"
      ```

      Peek at what is parked, without acknowledging it:

      ```
      gcloud pubsub subscriptions pull ${var.dead_letter_subscription} --limit=10 --format=json
      ```

      Once the cause is fixed, a real state change re-drives the finding: mute it, then unmute it. The worker triages it under its own key.
    EOT
  }
}

