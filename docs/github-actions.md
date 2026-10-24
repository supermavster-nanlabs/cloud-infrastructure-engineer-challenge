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

The state bucket, the `dev` and `prod` GitHub environments, and the AWS credentials
(an OIDC role or access keys) are set up once. The commands are in
[runbook.md](runbook.md), parts 2, 3 and 5.

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
- **Account ID in the logs.** The role ARN and the state bucket name carry the account
  ID, so both are secrets, which GitHub masks from the first step. The ID itself is
  masked once credentials are configured. Variables are not masked and are printed in
  each step's header, so do not keep anything sensitive in them.
- Logs and run summaries of a public repository are public. The
  endpoint URL printed after an apply is a public endpoint anyway.
