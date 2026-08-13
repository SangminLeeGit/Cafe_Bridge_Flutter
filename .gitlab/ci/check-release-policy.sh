#!/usr/bin/env bash
set -Eeuo pipefail

grep -Fq 'CI_PIPELINE_SOURCE:-}" == "push"' .gitlab/ci/report-failure.sh
grep -Fq 'EFFECTIVE_DRY_RUN=true' .gitlab/ci/report-failure.sh
grep -Fq 'export REPORT_COMMIT_SHA' .gitlab/ci/report-failure.sh
grep -Fq 'android_release_dry_run:' .gitlab-ci.yml
test "$(grep -c 'tags: \[android-release\]' .gitlab-ci.yml)" -eq 5
! grep -Fq 'tags: [cafe-bridge-android-release]' .gitlab-ci.yml
printf 'Release reporting policy is consistent\n'
