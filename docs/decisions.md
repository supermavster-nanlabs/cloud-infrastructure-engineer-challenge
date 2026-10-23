# Decisions

What was chosen, what was rejected, and what was left out on purpose. The brief
asks for a clear, focused solution that is easy to review, so the default answer
to "should this be here?" was no.

## Choices

**Terraform.** The challenge prefers it, the plan is a reviewable diff, the AWS
provider is mature, and `terraform test` can mock AWS so everything is tested
without an account. CloudFormation, SAM and CDK tie the work to AWS and make the
change harder to review. OpenTofu would probably work unchanged but was not
tested.

**One root, five modules, shared S3 state.** Each module has one job (network,
database, lambda, api, monitoring) and its own tests. The state sits in S3 with
the native lock file, so `make` and the GitHub workflow work on the same
infrastructure; GitHub runners are ephemeral, so local state would be lost after
every run. The bucket is created once with `make state-bucket`, and each
environment and region has its own state key.

**Two ways to deploy, one set of commands.** `make` for people who have the tools,
and a `workflow_dispatch` workflow for people who would rather click. The workflow
only calls the make targets, so there is one implementation to review and both
paths always act on the same state. It uses OIDC when a role is configured and
access keys otherwise, and prod waits for a reviewer. `apply` plans and applies in
the same run instead of passing a plan between jobs, which keeps the workflow
simple; run `plan` first to read it before applying.

**RDS PostgreSQL, not a database on EC2.** AWS handles backups, point-in-time
restore, Multi-AZ failover, patching and encryption. EC2 would mean owning all of
that, plus SSH access and operating-system patching, for no benefit.

**HTTP API, not REST API.** Cheaper and simpler. The REST-only features (WAF, API
keys, usage plans) are not needed for one public route. The cost is that WAF
would need CloudFront in front.

**The database password is created by RDS.** It is stored in Secrets Manager,
rotated by RDS, and never appears in the code, the variables or Terraform state.
The function reads it on every call and opens a fresh connection, so rotation
needs no cache and no retry logic. The cost is one Secrets Manager call per
request, which is negligible at this scale.

**Verified TLS.** The server requires TLS (`rds.force_ssl`, set explicitly in a
parameter group rather than relied on as a default) and the function verifies the
certificate chain and the hostname against the bundled RDS certificate bundle.
Encrypting without checking the certificate would stop eavesdropping but not
impersonation.

**Instance details come from Terraform.** The response includes the instance
class, Multi-AZ flag and zone, passed to the function as environment variables.
That avoids an RDS API call, an extra permission and extra code. The trade-off:
it is Terraform's view, not a live lookup, so it can lag behind a failover.

**One NAT gateway by default.** The Lambda needs outbound access to reach Secrets
Manager, and the brief asks for a NAT gateway in a public subnet. One shared
gateway costs half of one per zone; `nat_gateway_per_az = true` gives each zone
its own, at the price of the extra gateway. In the shared layout the zone holding
the gateway is a single point of failure for outbound access.

**Test-friendly defaults.** Deletion protection is off and the final snapshot is
skipped, so a test deployment can be destroyed with one command. The variable
descriptions say to change both in production.

**Checks run the same way everywhere.** CI calls the same Makefile targets a
developer does. checkov runs through `uvx` at an exact version, so results do not
depend on what happens to be installed.

## Left out on purpose

Each of these is a good idea at larger scale and would grow what a reviewer has to
read. None is needed to meet the brief.

| Left out | What I would do for production |
| -------- | ------------------------------ |
| Customer-managed KMS keys | Keys per purpose (data, logs) with rotation. Storage and the secret are already encrypted with AWS-managed keys |
| VPC flow logs | Enable them to a log group with retention |
| A managed state bucket | Create the bucket with Terraform in its own small root (versioning, KMS, a TLS-only policy, `prevent_destroy`) instead of the four CLI commands in `make state-bucket` |
| More environments | Staging, and separate AWS accounts per environment instead of one account with a name suffix |
| Database logs and enhanced monitoring | Export the PostgreSQL log to a log group with retention and a KMS key |
| More alarms | Storage, memory, connections, Lambda throttles and duration, NAT port exhaustion |
| Lambda concurrency cap | Cap it, so a slow database cannot be flooded with connections (needs spare account quota). The API throttle already limits the rate |
| Connection reuse and a secret cache | Reuse one connection per warm instance and cache the secret for a few minutes, once the request rate justifies the complexity |
| A dedicated database user | The function uses the master user. Create a read-only user and use IAM authentication |
| VPC endpoints for Secrets Manager | They would let the security group drop the open HTTPS egress rule and remove the dependency on the NAT gateway |
| Authentication, WAF or CloudFront | A JWT authorizer, and CloudFront with WAF in front of the API |
| RDS Proxy | Connection pooling once there are many concurrent clients |
| Dependency update automation | Dependabot for the pinned actions, providers and Python lockfile |

## What only a deployment can show

The live endpoint and the CloudWatch logs; that the invoke permission's source ARN
matches the `$default` stage; that alarms can publish to the topic; and TLS
verification against a real RDS certificate. The README says how to deploy and
verify them.
