#!/bin/bash
# Run this BEFORE triggering the workflow. It watches for a new runner pod
# and immediately dumps its logs the moment it's created, so we don't lose
# the crash reason to ARC's fast cleanup of completed/failed ephemeral pods.

NAMESPACE="arc-systems"
SEEN_FILE="/tmp/seen_pods.txt"
touch "$SEEN_FILE"

echo "Watching for new runner pods in ${NAMESPACE}... (Ctrl+C to stop)"

while true; do
  PODS=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep runner | grep -v listener | awk '{print $1}')
  for POD in $PODS; do
    if ! grep -q "^${POD}$" "$SEEN_FILE"; then
      echo "$POD" >> "$SEEN_FILE"
      echo "=== New pod detected: $POD ==="
      LOGFILE="/tmp/runner-log-${POD}.txt"
      # Poll logs aggressively for a few seconds - catches output even if
      # the pod terminates almost immediately
      for i in {1..20}; do
        kubectl logs "$POD" -n "$NAMESPACE" --all-containers > "$LOGFILE" 2>&1
        if [ -s "$LOGFILE" ]; then
          echo "--- Logs for $POD (saved to $LOGFILE) ---"
          cat "$LOGFILE"
          echo "--- end logs ---"
          break
        fi
        sleep 0.3
      done
      # Also grab describe output - shows exit code/reason even with empty logs
      kubectl describe pod "$POD" -n "$NAMESPACE" > "/tmp/runner-describe-${POD}.txt" 2>&1
      echo "Describe output saved to /tmp/runner-describe-${POD}.txt"
    fi
  done
  sleep 0.3
done
