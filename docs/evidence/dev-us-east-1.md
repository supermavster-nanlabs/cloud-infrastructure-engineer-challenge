# First deployment: dev in us-east-1

Recorded on 2026-10-24 (UTC), in a personal AWS account (ID redacted below). The stack
was applied with `make`, checked, planned again from the GitHub workflow, and destroyed
from the GitHub workflow. It existed for about an hour and a half.

## What was run

| Step | How | Result |
| ---- | --- | ------ |
| State bucket | `make state-bucket` | created (versioned, encrypted, public access blocked) |
| Plan | `make plan ENV=dev REGION=us-east-1` | 47 to add, 0 to change, 0 to destroy |
| Apply | `make apply ENV=dev REGION=us-east-1` | 47 added |
| Verify | `make verify`, then `curl` | HTTP 200, shown below |
| Plan again | workflow `deploy`, action `plan`, from `main` before the fixes | 1 change: a permanent diff on `rds.force_ssl`, fixed afterwards (see below) |
| Plan again, after the fix | workflow `deploy`, action `plan`, from `main` ([run](https://github.com/supermavster-nanlabs/cloud-infrastructure-engineer-challenge/actions/runs/40050082369)) | **No changes**, so `make` and the workflow share one state |
| Destroy | workflow `deploy`, action `destroy`, `confirm=dev` ([run](https://github.com/supermavster-nanlabs/cloud-infrastructure-engineer-challenge/actions/runs/40050161154)) | 47 destroyed in 5 minutes |

The apply and the endpoint checks used an SSO profile with administrator access. The
workflow used an IAM role assumed through GitHub's OIDC provider.

## The endpoint

`GET /info` answered `200` on the first call after the apply (a cold start, see the logs
below). The response was:

```json
{
  "status": "ok",
  "timestamp": "2026-10-24T00:13:47Z",
  "request_id": "41fb9ee6-1006-4b85-b8bf-68b812849bff",
  "database": {
    "connected": true,
    "engine": "postgres",
    "version": "17.9",
    "database": "appdb",
    "in_recovery": false,
    "uptime_seconds": 534,
    "tls": true,
    "latency_ms": 225.9
  },
  "instance": {
    "class": "db.t4g.micro",
    "multi_az": false,
    "availability_zone": "us-east-1b",
    "backup_retention_days": 7
  }
}
```

Only that route exists. Every other path and method answered `404`:

| Request | Status |
| ------- | ------ |
| `GET /info` | 200 |
| `GET /` | 404 |
| `GET /other` | 404 |
| `POST /info` | 404 |
| `DELETE /info` | 404 |

## CloudWatch logs

`aws logs tail /aws/lambda/info-api-dev-info` showed, for the request above (the
function ARN carries the account ID, redacted here):

```text
platform.start   requestId 41fb9ee6-1006-4b85-b8bf-68b812849bff  functionArn arn:aws:lambda:us-east-1:<ACCOUNT_ID>:function:info-api-dev-info
platform.report  requestId 41fb9ee6-1006-4b85-b8bf-68b812849bff  durationMs 1111.6  initDurationMs 424.6  maxMemoryUsedMB 96 of 256  status success
platform.start   requestId c55258c1-74ea-4331-961a-e073bd24a894
platform.report  requestId c55258c1-74ea-4331-961a-e073bd24a894  durationMs 290.65  status success
```

The first request is a cold start (1.1 s, including the secret read and the TLS
handshake); the next one took 291 ms. The `requestId` in the logs is the same value the
response returns as `request_id`. The function writes a line of its own only on failure,
so a successful request leaves just these platform records.

## What was checked in the account

Read with the AWS CLI after the apply:

| Check | Observed |
| ----- | -------- |
| RDS instance | `available`, `PubliclyAccessible` false, storage encrypted, single AZ |
| Master password | managed by RDS in Secrets Manager, status `active` |
| Parameter group | `in-sync`; `rds.force_ssl` is `1` |
| Lambda | `python3.13`, `arm64`, attached to 2 subnets, state `Active` |
| Data subnets' route table | one route, `10.20.0.0/16 -> local`: no route out |
| Alarms | `lambda-errors` OK; `api-5xx` and `rds-cpu-high` `INSUFFICIENT_DATA` (no data points yet) |
| State | one object, `info-api/dev/us-east-1/terraform.tfstate` |

After the destroy, the same account had no RDS instance or snapshot, no NAT gateway or
Elastic IP, no VPC, Lambda, API, log group, alarm, SNS topic or Secrets Manager secret
from this stack. Only the state bucket and the deploy role (created for the workflow)
remained.

## What the deployment found

Running it against a real account caught three problems that the offline checks could not.
All three are fixed.

- **A permanent plan diff** on `aws_db_parameter_group`: the code declared `rds.force_ssl`
  with the apply method `immediate`, while RDS reports `pending-reboot`, so every plan
  proposed a change that never settled. The mocked provider cannot show this. Fixed in
  [#7](https://github.com/supermavster-nanlabs/cloud-infrastructure-engineer-challenge/pull/7),
  with a test.
- **The account ID in a public log.** The workflow printed the role ARN and the bucket name,
  which carry the account ID, in step headers before GitHub's masking is active, while the
  documentation said the ID was masked. Both are now secrets. Fixed in
  [#8](https://github.com/supermavster-nanlabs/cloud-infrastructure-engineer-challenge/pull/8).
  The two runs made before the fix still show the ID in their logs.
- **OIDC `AssumeRoleWithWebIdentity` denied.** Repositories created after 15 July 2026 use
  an immutable subject (`repo:OWNER@ID/REPO@ID`), and the runbook's trust policy had the
  plain name. The runbook now reads the prefix from the repository's settings (same PR).

Two smaller runbook mistakes were corrected at the same time: the Lambda's log group name,
and the claim that each request logs a line of its own.

## What was not tested

- The workflow's `apply` action (the apply here was `make apply`) and its `unlock` action.
- The access-key option for the workflow; only the OIDC role was used.
- `prod`: its settings (a NAT gateway per zone, a standby database, deletion protection),
  its required reviewer, and destroying it.
- Any region other than `us-east-1`.
- A failing database (the `503` categories are covered by the function's tests only), and
  the alarms firing.
- The cost: no billing data was read. At the rates in the README the run is on the order of
  ten cents, with the RDS rate unverified.
