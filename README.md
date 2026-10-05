# Flare PR Security Check

**Catch IAM misconfigurations, overly broad permissions, and privilege escalation paths before they reach production.** Flare PR Security Check uses AI to review your Terraform, CloudFormation, and IAM policy changes on every pull request -- posting findings with severity scores, plain-English explanations, and specific fix suggestions directly as a PR comment. No rules to maintain, no connector required -- just add your Flare API key and start catching what static scanners miss.

## Quick start

```yaml
name: Security Review
on:
  pull_request:
    paths:
      - '**/*.tf'
      - '**/*.tfvars'
      - '**/cloudformation/**'
      - '**/*-policy.json'
      - '**/*-role.json'

jobs:
  flare:
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
      contents: read
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - uses: tryflare-ai/pr-security-check@v1
        with:
          token: ${{ secrets.FLARE_API_KEY }}
```

## Setup

1. Sign up at [tryflare.ai](https://tryflare.ai)
2. Go to **Settings > API Keys** and create a key
3. Add the key as a repository secret named `FLARE_API_KEY`
4. Add the workflow above to `.github/workflows/flare.yml`

### Pull requests from forks

GitHub does not pass repository secrets to workflows triggered by pull requests from forks (or by Dependabot). In that case the action skips the review with a notice and exits successfully, so fork contributors are never blocked by a missing key.

**Use the `pull_request` trigger, not `pull_request_target`.** `pull_request_target` runs with your secrets and a write token in the context of the base repository, so combining it with a checkout of the PR's code lets a fork author run arbitrary code in your workflow. The action is not designed for `pull_request_target` and emits a warning if it detects it.

## Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `token` | Yes | -- | Flare API key (`flr_pr_...`). Generate at tryflare.ai/settings. |
| `fail-on` | No | `critical` | Minimum severity to fail the check: `critical`, `high`, `medium`, `low`, `none`. |
| `comment` | No | `true` | Post findings as a PR comment. |
| `paths` | No | -- | Custom file patterns (comma-separated). Overrides default IaC patterns. |
| `api-url` | No | `https://www.tryflare.ai/api/webhooks/pr-check` | API endpoint. Override for self-hosted. |

## Outputs

| Output | Description |
|--------|-------------|
| `findings-count` | Total number of security findings |
| `critical-count` | Number of critical-severity findings |
| `high-count` | Number of high-severity findings |

## Default file patterns

The action reviews changes to these files by default:

- `*.tf`, `*.tfvars` -- Terraform
- `*-policy.json`, `*-role.json` -- IAM policies
- `*.sentinel` -- Sentinel policies
- `cloudformation/` -- CloudFormation templates
- `iam/` -- IAM configuration directories
- `k8s/`, `helm/` -- Kubernetes manifests

Override with the `paths` input for custom patterns.

## What it detects

- Overly broad IAM roles (`roles/editor`, `roles/owner`, wildcard permissions)
- Missing conditions on IAM bindings
- Public access (`allUsers`, `allAuthenticatedUsers`, `0.0.0.0/0`)
- Privilege escalation paths (`setIamPolicy`, `actAs`, `sts:AssumeRole`)
- Hardcoded secrets and credentials
- Overly permissive network rules
- Missing encryption and audit logging
- Dangerous default configurations

## How it works

1. The action identifies which changed files match IaC patterns
2. Extracts the diff for those files
3. Sends the diff to Flare's API for AI-powered review
4. Posts findings as a PR comment with severity, explanation, and fix suggestions
5. Fails the check if findings meet the `fail-on` threshold

Flare uses Claude to analyze diffs contextually -- it catches security issues that rule-based scanners miss, like subtle privilege escalation paths or misconfigured trust relationships.

## PR comment

When findings are detected, a comment is posted on the PR:

> ## Flare Security Review
>
> **1 critical** | **2 high** | 3 file(s) analyzed
>
> ---
>
> ### Critical
>
> #### `infra/iam.tf:23` -- Overly broad IAM role
>
> This binding grants `roles/editor` to a service account...
>
> **Fix:** Replace with a custom role or `roles/cloudfunctions.developer`.

When re-running on the same PR, the existing comment is updated (not duplicated).

## Rate limits

PR checks share the Flare daily analysis limit (10/day on free tier). The action gracefully handles rate limits -- it posts a warning but does not fail the workflow.

## Learn more

- [Cloud anomaly detection for GCP and AWS](https://tryflare.ai/cloud-anomaly-detection)
- [Flare documentation](https://docs.tryflare.ai)

## License

MIT
