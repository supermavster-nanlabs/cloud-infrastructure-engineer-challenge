# Deploy from GitHub Actions

The `deploy` workflow does the same thing as `make plan`, `apply`, `destroy` and
`unlock`, from the Actions tab, for anyone who would rather not run `make`. It
calls the same Makefile targets, so both always work on the same state.

Open **Actions > deploy > Run workflow** and choose:

| Input | Values | Notes |
| ----- | ------ | ----- |
| environment | `dev`, `prod` | Picks the settings in `terraform/environments/` and the GitHub environment that holds the credentials |
| region | `us-east-1`, `us-east-2`, `us-west-2`, `eu-west-1`, `eu-central-1`, `sa-east-1` | Each environment and region pair has its own state |
| action | `plan`, `apply`, `destroy`, `unlock` | See below |
| confirm | the environment name | Required for `destroy` and `unlock` |
| lock_id | the lock ID | Required for `unlock` |

- **plan** shows what would change and saves nothing else.
- **apply** plans, then applies that plan, in the same run. The plan is printed in
  the log before it is applied. To read it first, run `plan` and then `apply`.
- **destroy** plans a destroy, then applies it. Type the environment name in
  `confirm`. Prod's deletion protection makes it fail until
  `db_deletion_protection = false` is applied first, on purpose.
- **unlock** releases a stuck state lock. Terraform prints the lock ID when a
  run is interrupted ("state is locked"); paste it into `lock_id`.

Runs for the same environment and region queue instead of overlapping, and a run
that is changing infrastructure is never cancelled.

## One-time setup

**1. The state bucket** (once per AWS account; the name must be globally unique):

```bash
STATE_BUCKET=<globally-unique-name> make state-bucket
gh variable set STATE_BUCKET --body <globally-unique-name>
```

If the bucket is not in `us-east-1`, also set the `STATE_REGION` variable to its
region.

**2. GitHub environments.** Create `dev` and `prod` under Settings >
Environments. For `prod`, add yourself as a required reviewer: every run against
prod then waits for approval before it starts.

**3. AWS access.** Choose one. The workflow uses the role if the `AWS_ROLE_ARN`
variable is set, and the keys otherwise.

*Option A: OIDC role (recommended, no stored keys).* Create the GitHub identity
provider once per account, then a role the workflow can assume:

```bash
aws iam create-open-id-connect-provider --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com
```

The role's trust policy lets only this repository's environments assume it:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": "repo:<OWNER>/<REPO>:environment:*" }
    }
  }]
}
```

```bash
gh variable set AWS_ROLE_ARN --env dev  --body arn:aws:iam::<ACCOUNT_ID>:role/<ROLE>
gh variable set AWS_ROLE_ARN --env prod --body arn:aws:iam::<ACCOUNT_ID>:role/<ROLE>
```

*Option B: access keys.* Create an IAM user for this, and store its keys as
secrets of each environment (the value is read from standard input, so it does not
end up in your shell history):

```bash
gh secret set AWS_ACCESS_KEY_ID     --env dev
gh secret set AWS_SECRET_ACCESS_KEY --env dev
```

Keys are long-lived credentials; prefer the role, and rotate keys if you use them.
Environment secrets and variables can differ between `dev` and `prod`, so the two
can point at different AWS accounts.

## Permissions

The role or user needs to create what the stack contains: a VPC with its routes,
NAT gateways and security groups; an RDS instance; a Lambda function and its IAM
role; an API Gateway API; CloudWatch log groups and alarms; an SNS topic; and to
read and write the state bucket. In a sandbox account an administrator-style role
is the simplest. Scoping it down to exactly these actions is not done here and is
worth doing before pointing this at an account that matters.

## Things to know

- **Not exercised yet.** The workflow is linted (actionlint) and passes checkov, but
  it has not run against AWS. The first real run is the first test of the OIDC and
  key paths, of the state bucket access and of `terraform force-unlock`.
- **One region per environment per account.** IAM role names are global, so deploying
  the same environment to two regions of one account collides on the Lambda's role.
  Use a different account, or a different environment name, for the second region.
- **The AWS account ID is masked** in the logs, because this repository is public.
- Logs and run summaries of a public repository are public. The
  endpoint URL printed after an apply is a public endpoint anyway.
