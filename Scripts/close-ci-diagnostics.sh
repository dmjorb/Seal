#!/usr/bin/env bash
set -euo pipefail

if ! command -v gh >/dev/null 2>&1 || [[ -z "${GH_TOKEN:-}" ]]; then
    exit 0
fi

title="Automated CI diagnostics"
issue_number="$({
    gh issue list \
        --state open \
        --search "\"$title\" in:title" \
        --json number,title \
        --jq ".[] | select(.title == \"$title\") | .number" 2>/dev/null || true
} | head -n 1)"

if [[ -n "$issue_number" ]]; then
    run_url="https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
    gh issue close "$issue_number" \
        --comment "Build [$GITHUB_RUN_NUMBER]($run_url) completed successfully; closing the automated diagnostics issue." \
        >/dev/null 2>&1 || true
fi
