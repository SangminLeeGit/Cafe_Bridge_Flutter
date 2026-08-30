#!/usr/bin/env bash

# Write stable duration records to both the GitLab trace and the local journal.
# The journal write is best-effort so an unavailable logger cannot fail a build.
ci_timing() {
  local step="$1"
  local started_at ended_at duration_seconds status
  shift

  started_at="$(date +%s)"
  printf 'CI_TIMING event=start step=%s project=%s job=%s pipeline=%s\n' \
    "${step}" "${CI_PROJECT_PATH:-unknown}" "${CI_JOB_NAME:-unknown}" "${CI_PIPELINE_ID:-unknown}"

  if "$@"; then
    status=0
  else
    status=$?
  fi

  ended_at="$(date +%s)"
  duration_seconds="$((ended_at - started_at))"
  printf 'CI_TIMING event=finish step=%s status=%s duration_s=%s project=%s job=%s pipeline=%s\n' \
    "${step}" "${status}" "${duration_seconds}" "${CI_PROJECT_PATH:-unknown}" "${CI_JOB_NAME:-unknown}" "${CI_PIPELINE_ID:-unknown}"
  if command -v logger >/dev/null 2>&1; then
    logger -t ci-timing -- "event=finish step=${step} status=${status} duration_s=${duration_seconds} project=${CI_PROJECT_PATH:-unknown} job=${CI_JOB_NAME:-unknown} pipeline=${CI_PIPELINE_ID:-unknown}" || true
  fi
  return "${status}"
}
