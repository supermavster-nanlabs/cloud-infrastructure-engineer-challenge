# Runbook: deploy from zero

How to go from an empty AWS account to a working `GET /info` endpoint, and back to
an empty account. Follow it top to bottom. It covers both ways to deploy, which
act on the same state:

| Path | Use it when | Needs on your machine |
| ---- | ----------- | --------------------- |
| **A. `make`** | you are comfortable in a terminal | Terraform, uv, AWS CLI, jq |
| **B. GitHub workflow** | you would rather click in the Actions tab | a GitHub account (the CLI helps, but is optional) |

Parts 1, 3, 6 and 7 are shared. Part 2 gets credentials, 4 is path A, 5 is path B.
Replace everything in `<angle brackets>` with your own value before you run a
command. Anything done in the AWS web console is described by its menu path;
labels change over time, so the CLI form is given where there is one.

Whatever you deploy costs money while it runs. The NAT gateway and the database
bill by the hour, so a short test is cheap and a forgotten one is not. Part 7
removes everything. See the cost note in the [README](../README.md#deploy).

## 1. Before you start

**1.1 An AWS account you can break.** Use a sandbox or personal account, not one
that matters. You need one administrator identity to create the others (an IAM
Identity Center user, or an IAM user with `AdministratorAccess`). Do not use the
root user for day-to-day work. Setting an AWS budget alert before the first deploy
is a good habit.

**1.2 Tools.** Check what you have:

```bash
terraform version     # 1.11 or newer
uv --version          # fetches Python 3.13 for the build
aws --version         # AWS CLI v2
jq --version
gh --version          # only for the GitHub path, and optional
```

Path B needs none of them except `gh` if you want to configure GitHub from the
terminal; everything `gh` does here can also be done in the repository's Settings.

**1.3 Pick three values** and keep them handy:

| Name | Example | Rule |
| ---- | ------- | ---- |
| `STATE_BUCKET` | `jane-info-api-state-4821` | globally unique across all of AWS, lowercase |
| region | `us-east-1` | the default; any region works for the stack |
| environment | `dev` | `dev` for a test, `prod` only if you mean it |

**1.4 Get the code.** For path A, clone it. For path B you need your own GitHub
copy so that you can set secrets and run workflows: use **Fork** on GitHub, then
open the **Actions** tab of your fork and enable workflows (forks start with them
disabled).

```bash
git clone git@github.com:<OWNER>/<REPO>.git
cd <REPO>
```

## 2. Get credentials

Choose by path. Check that they work before going on.

### 2A. For `make` (path A)

Either an SSO profile:

```bash
aws configure sso --profile info-api      # answer the prompts
aws sso login --profile info-api
export AWS_PROFILE=info-api
```

or an IAM user's access keys, entered at the prompt so they stay out of your shell
history:

```bash
aws configure --profile info-api
export AWS_PROFILE=info-api
```

Check which account you are about to change:

```bash
aws sts get-caller-identity
```

If the account ID is not the one you intend, stop and fix the profile.

### 2B. For the GitHub workflow (path B)

The workflow needs its own AWS identity. Use the role (B1) when you can: it stores
no long-lived credential. Use access keys (B2) if you cannot create an OIDC provider.
The workflow uses the role if the `AWS_ROLE_ARN` secret exists, and the keys
otherwise. The role ARN is stored as a secret, not a variable, because it contains
your account ID and GitHub prints variables in the log of every step.

Run these with your administrator identity. Replace `<OWNER>/<REPO>` with your
fork. The environments must exist before you store anything in them, so do
part 5.2 first.

**B1. OIDC role (recommended).**

```bash
export GH_REPO=<OWNER>/<REPO>
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# GitHub's subject prefix for this repository. Repositories created after
# 15 July 2026 use immutable IDs in it (repo:OWNER@ID/REPO@ID), so do not type it.
SUB_PREFIX=$(gh api "repos/${GH_REPO}/actions/oidc/customization/sub" --jq '.sub_claim_prefix // empty')
SUB_PREFIX=${SUB_PREFIX:-repo:${GH_REPO}}
echo "$SUB_PREFIX"

# Once per account. "EntityAlreadyExists" means it is already there: carry on.
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com

# Only this repository's environments may assume the role.
TRUST=$(mktemp)
cat > "$TRUST" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": "${SUB_PREFIX}:environment:*" }
    }
  }]
}
EOF

aws iam create-role --role-name info-api-deploy --assume-role-policy-document "file://${TRUST}"
aws iam attach-role-policy --role-name info-api-deploy \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

for E in dev prod; do
  printf '%s' "arn:aws:iam::${ACCOUNT_ID}:role/info-api-deploy" | gh secret set AWS_ROLE_ARN --env "$E"
done
```

`AdministratorAccess` is the simplest choice for a sandbox. Scoping the role down is
not done here; see the permissions note in [github-actions.md](github-actions.md).

**B2. Access keys.** The key is written to a private temporary file, passed to
GitHub through standard input (never on a command line), and deleted.

```bash
export GH_REPO=<OWNER>/<REPO>

aws iam create-user --user-name info-api-deploy
aws iam attach-user-policy --user-name info-api-deploy \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

KEYFILE=$(mktemp)
aws iam create-access-key --user-name info-api-deploy --query AccessKey --output json > "$KEYFILE"
for E in dev prod; do
  jq -j .AccessKeyId     "$KEYFILE" | gh secret set AWS_ACCESS_KEY_ID     --env "$E"
  jq -j .SecretAccessKey "$KEYFILE" | gh secret set AWS_SECRET_ACCESS_KEY --env "$E"
done
rm -f "$KEYFILE"
```

In the console, the equivalent is IAM > Users > Create user > Security credentials >
Create access key, then GitHub > Settings > Environments > (dev or prod) >
Add environment secret. The secret access key is shown once.

These are long-lived credentials: delete them when you are done (part 7), and
never paste them into a chat, an issue or a commit.

Both options give `dev` and `prod` the same identity. To keep prod apart, create
the identity in a different AWS account and store that account's values in the
`prod` environment only.

## 3. Create the state bucket (once per account)

The state lives in S3 so that `make` and the workflow see the same infrastructure.

```bash
export STATE_BUCKET=<globally-unique-name>
make state-bucket
```

It creates a bucket that is versioned, encrypted and closed to the public. If the
name is taken, AWS says `BucketAlreadyOwnedByYou` (yours, fine) or
`BucketAlreadyExists` (someone else's: choose another).

If you use a region other than `us-east-1` for the bucket, also set
`STATE_REGION=<region>` here and in part 5.

## 4. Path A: deploy with `make`

```bash
make plan   ENV=dev REGION=us-east-1     # builds the package, saves the plan
```

Read the plan. A first deploy creates a few dozen resources (VPC, subnets, NAT gateway,
database, function, API, alarms); look for anything you did not expect. Then:

```bash
make apply  ENV=dev REGION=us-east-1     # applies exactly the plan you read
make verify ENV=dev REGION=us-east-1     # calls the endpoint and prints the JSON
make logs   ENV=dev REGION=us-east-1     # tails the Lambda's CloudWatch logs
```

The first apply takes several minutes; the database is the slow part. Optional
settings go in as environment variables, for example
`TF_VAR_alert_email=you@example.com make plan` (confirm the email AWS sends).

Jump to part 6 to check the result, and part 7 to tear down.

## 5. Path B: deploy from the GitHub dashboard

**5.1 Sign in the CLI (optional).** The commands below use `gh`. Skip it and use
Settings in the browser if you prefer.

```bash
gh auth login
export GH_REPO=<OWNER>/<REPO>
```

**5.2 Create the environments.** Do this before storing credentials. If a workflow
runs against an environment that does not exist, GitHub creates it with no
protection, so create `prod` yourself first.

```bash
gh api -X PUT repos/$GH_REPO/environments/dev
printf '{"reviewers":[{"type":"User","id":%s}]}' "$(gh api user --jq .id)" \
  | gh api -X PUT repos/$GH_REPO/environments/prod --input -
```

In the browser: Settings > Environments > New environment, and for `prod` tick
Required reviewers and add yourself. Environment protection works on public
repositories on every plan; on a private repository it needs GitHub Pro or Team
(GitHub documents this, and says protection is ignored otherwise).

**5.3 Store the state bucket.** The name is a secret, not a variable: bucket names
often contain the account ID, and GitHub prints variables in the log of every step
while it masks secrets from the first one. The region is not sensitive.

```bash
printf '%s' "$STATE_BUCKET" | gh secret set STATE_BUCKET
gh variable set STATE_REGION --body us-east-1     # only if the bucket is elsewhere
```

**5.4 Store the AWS credentials** with B1 or B2 from part 2B. Check:

```bash
gh secret list --env dev         # AWS_ROLE_ARN (B1), or AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY (B2)
```

**5.5 Run it.** In your fork: **Actions > deploy > Run workflow**, then fill in:

| Input | First run |
| ----- | --------- |
| environment | `dev` |
| region | `us-east-1` |
| action | `plan` |

Click **Run workflow**, open the run, and read the plan in the **Run** step. The
terminal equivalent is:

```bash
gh workflow run deploy.yml -f environment=dev -f region=us-east-1 -f action=plan
gh run watch --exit-status
```

Run it again with action `apply`. It plans and then applies that plan in the same
run. When it finishes, the run's **Summary** page shows the line
`Endpoint: https://...`. A `prod` run waits first: open the run and approve it
under **Review deployments**.

The other actions are `destroy` and `unlock`; both need the environment name in
`confirm`, and `unlock` also needs the lock ID. Details are in
[github-actions.md](github-actions.md).

## 6. Check it works

With path A, `make verify` already did this. With path B, use the endpoint from the
run summary:

```bash
curl -sS "<ENDPOINT_FROM_THE_SUMMARY>" | jq .
```

A healthy answer has `"status": "ok"` and `database.connected: true`. The same
information is in the README. A `503` right after an apply usually means the
database was still starting: wait a minute and retry.

Logs: path A has `make logs`. Otherwise, in the CloudWatch console open Logs > Log
groups and find `/aws/lambda/info-api-dev-info`, or run
`aws logs tail /aws/lambda/info-api-dev-info --since 15m --region us-east-1`.
Every request leaves START and REPORT records with its `requestId`, the same value
the response returns as `request_id`. The function writes its own line only when
something fails.

## 7. Tear it down and clean up

Do this when the test is over. Order matters: the stack first, then the bucket,
then the credentials.

**7.1 Destroy the stack.**

```bash
make destroy ENV=dev REGION=us-east-1 CONFIRM=dev       # then answer yes
```

or **Actions > deploy** with action `destroy` and `confirm` set to `dev`. Prod has
deletion protection on: set `db_deletion_protection = false` in
`terraform/environments/prod.tfvars`, apply that, then destroy. Prod also takes a
final snapshot (`<name>-final`), which stays and bills until you delete it.

**7.2 Remove the state bucket** once no environment uses it. It is versioned, so it
must be emptied of every version before it can be deleted; the S3 console's
Empty and Delete buttons do that. The bucket costs almost nothing, so keep it if
you will deploy again.

**7.3 Revoke the credentials** you created for this:

```bash
# B1: the role and the provider
aws iam detach-role-policy --role-name info-api-deploy --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-role --role-name info-api-deploy
aws iam delete-open-id-connect-provider \
  --open-id-connect-provider-arn arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com

# B2: the user and its key
aws iam list-access-keys --user-name info-api-deploy
aws iam delete-access-key --user-name info-api-deploy --access-key-id <KEY_ID>
aws iam detach-user-policy --user-name info-api-deploy --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-user --user-name info-api-deploy
```

Delete the OIDC provider only if nothing else in the account uses it. Then remove
the GitHub secrets and variables (Settings, or `gh secret delete` and
`gh variable delete`).

## 8. When something goes wrong

| What you see | Likely cause | What to do |
| ------------ | ------------ | ---------- |
| `Set the STATE_BUCKET secret` (workflow) | Part 5.3 not done | Set the repository secret |
| `Set the AWS_ROLE_ARN secret ... or the AWS_ACCESS_KEY_ID ...` | Part 5.4 not done, or set on the wrong environment | Store the credentials in the environment you chose when running |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The trust policy's `sub` does not match what GitHub sends. Most often the repository uses immutable subjects (`repo:OWNER@ID/REPO@ID`), the default for repositories created after 15 July 2026, and the policy has the plain name. Or the job names no environment | Run `gh api repos/<OWNER>/<REPO>/actions/oidc/customization/sub --jq .sub_claim_prefix` and make the policy's `sub` that value plus `:environment:*` (`aws iam update-assume-role-policy`) |
| `ExpiredToken`, or the SSO login expired (path A) | Short-lived credentials ran out | `aws sso login --profile info-api` |
| `set STATE_BUCKET to your state bucket` (make) | `STATE_BUCKET` is not exported in this shell | `export STATE_BUCKET=...` |
| `BucketAlreadyExists` | Bucket names are global | Choose another name |
| `no saved plan for dev in us-east-1` | `make apply` before `make plan` for that environment and region | `make plan` first |
| `Error acquiring the state lock` | A run was interrupted | Copy the lock ID from the error, then `make unlock ENV=dev REGION=us-east-1 CONFIRM=dev LOCK_ID=<id>`, or the workflow's `unlock` |
| The `deploy` workflow is not in the Actions tab | Workflows are disabled on a fresh fork | Open Actions and enable them |
| A `prod` run never starts | It is waiting for the reviewer | Approve it under Review deployments |
| Creating the same environment in a second region fails on an IAM role | IAM role names are global in an account | Use another account, or another environment name |
| `destroy` fails deleting a subnet or security group | Lambda releases its network interfaces some time after the function is gone (how long was not measured) | Wait and run `destroy` again |
| `503` from the endpoint | Database still starting, or the NAT gateway not ready | Wait a minute and retry; `database.error` names the category |

The workflow prints errors with a `::error::` prefix, which shows as a red
annotation at the top of the run page.

## What this runbook did not test

It was run against a real account once, and that run corrected it three times (the
OIDC subject format, where the account ID shows in logs, and two details about the
logs). What that run covered: the state bucket, an OIDC role and its trust policy,
the GitHub environments and their secrets, a `make` plan, apply and verify, and the
workflow's `plan` and `destroy` actions. The account was a personal one, reached
through an SSO profile that already existed. The record is in
[evidence/dev-us-east-1.md](evidence/dev-us-east-1.md).

Not run: the access-key option (B2), `aws configure sso` and the other ways to create a
profile, forking and enabling workflows (part 1.4), the workflow's `apply` and
`unlock`, `prod`, regions other than `us-east-1`, and removing the state bucket (7.2)
and the role and provider (7.3). Whoever runs those first is their first test; fix this file where
it is wrong.
