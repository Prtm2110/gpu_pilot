#!/bin/bash

# Webhook payload template for Alertmanager
# This script shows how Alertmanager should format the webhook payload

# Scale Up Payload (when alert fires)
cat << 'EOF' > scale_up_payload.json
{
  "receiver": "cloud-scaler-up",
  "status": "firing",
  "alerts": [
    {
      "status": "firing",
      "labels": {
        "alertname": "TooManyPendingJobs",
        "service": "slurm",
        "action": "scale_up",
        "severity": "warning"
      },
      "annotations": {
        "summary": "High number of pending Slurm jobs",
        "description": "There are 25 pending jobs in the Slurm queue for more than 2 minutes"
      },
      "startsAt": "2025-08-07T10:30:00.000Z",
      "endsAt": "0001-01-01T00:00:00Z",
      "generatorURL": "http://prometheus:9090/graph?g0.expr=slurm_pending_jobs+%3E+20",
      "fingerprint": "abc123def456"
    }
  ],
  "groupLabels": {
    "alertname": "TooManyPendingJobs"
  },
  "commonLabels": {
    "alertname": "TooManyPendingJobs",
    "service": "slurm",
    "action": "scale_up",
    "severity": "warning"
  },
  "commonAnnotations": {
    "summary": "High number of pending Slurm jobs"
  },
  "externalURL": "http://alertmanager:9093",
  "version": "4",
  "groupKey": "{}:{alertname=\"TooManyPendingJobs\"}",
  "truncatedAlerts": 0,
  "action": "scale_up"
}
EOF

# Scale Down Payload (when alert resolves)
cat << 'EOF' > scale_down_payload.json
{
  "receiver": "cloud-scaler-down",
  "status": "resolved",
  "alerts": [
    {
      "status": "resolved",
      "labels": {
        "alertname": "TooManyPendingJobs",
        "service": "slurm",
        "action": "scale_up",
        "severity": "warning"
      },
      "annotations": {
        "summary": "High number of pending Slurm jobs",
        "description": "Pending jobs have been processed"
      },
      "startsAt": "2025-08-07T10:30:00.000Z",
      "endsAt": "2025-08-07T10:45:00.000Z",
      "generatorURL": "http://prometheus:9090/graph?g0.expr=slurm_pending_jobs+%3E+20",
      "fingerprint": "abc123def456"
    }
  ],
  "groupLabels": {
    "alertname": "TooManyPendingJobs"
  },
  "commonLabels": {
    "alertname": "TooManyPendingJobs",
    "service": "slurm",
    "action": "scale_up",
    "severity": "warning"
  },
  "commonAnnotations": {
    "summary": "High number of pending Slurm jobs"
  },
  "externalURL": "http://alertmanager:9093",
  "version": "4",
  "groupKey": "{}:{alertname=\"TooManyPendingJobs\"}",
  "truncatedAlerts": 0,
  "action": "scale_down"
}
EOF

echo "Created webhook payload templates:"
echo "- scale_up_payload.json"
echo "- scale_down_payload.json"
echo ""
echo "Test manually with:"
echo "curl -X POST -H 'Authorization: Bearer \$SCALER_SECRET_TOKEN' -H 'Content-Type: application/json' -d @scale_up_payload.json http://localhost:5000/scale"
