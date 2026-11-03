#!/usr/bin/env bash
set -Eeuo pipefail

grep -Fq 'CI_PIPELINE_SOURCE:-}" == "push"' .gitlab/ci/report-failure.sh
grep -Fq 'EFFECTIVE_DRY_RUN=true' .gitlab/ci/report-failure.sh
grep -Fq 'export REPORT_COMMIT_SHA' .gitlab/ci/report-failure.sh
grep -Fq 'must not use a loopback host on the dedicated Flutter runner' .gitlab/ci/android-release.sh
grep -Fq 'CI_RUNNER_DESCRIPTION' .gitlab/ci/android-release.sh
grep -Fq 'ct500-cafebridge-flutter-release' .gitlab/ci/android-release.sh
grep -Fq 'ct600-cafebridge-flutter-release' .gitlab/ci/android-release.sh
grep -Fq 'Android release requires a protected ref' .gitlab/ci/android-release.sh
test "$(grep -c 'tags: \[cafe-bridge-android-release\]' .gitlab-ci.yml)" -eq 5
! grep -Fq 'tags: [android-release]' .gitlab-ci.yml
python3 - <<'PY'
from pathlib import Path
import re

content = Path('.gitlab-ci.yml').read_text()

def job(name: str) -> str:
    match = re.search(rf'^{name}:\n(.*?)(?=^[^ \n][^\n]*:\n|\Z)', content, re.M | re.S)
    if not match:
        raise SystemExit(f'missing CI job: {name}')
    return match.group(0)

production = job('android_release_apk')
dry_run = job('android_release_dry_run')

if 'DRY_RUN: "true"' not in dry_run:
    raise SystemExit('dry-run release must force DRY_RUN=true')
if 'CI_COMMIT_BRANCH == "master"' not in dry_run:
    raise SystemExit('protected master pushes must build a dry-run artifact')
if 'CI_COMMIT_BRANCH == "master"' in production:
    raise SystemExit('protected master pushes must not register production APKs')
if '$DRY_RUN == "false"' not in production:
    raise SystemExit('production registration must require an explicit false dry-run value')
if '$DRY_RUN == "true"' not in dry_run:
    raise SystemExit('explicit dry runs must build a signed artifact')
PY
printf 'Release reporting policy is consistent\n'
