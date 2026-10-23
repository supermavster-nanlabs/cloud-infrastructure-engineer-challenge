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

**One root, five modules, local state.** `terraform init && terraform apply` works
with defaults and no settings file, which is what a reviewer wants. Each module
has one job (network, database, lambda, api, monitoring) and its own tests.
State is local; the README shows the three lines that move it to S3.

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
| Remote state and locking | S3 backend with `use_lockfile`, from a small bootstrap step that creates a locked-down bucket |
| Separate dev and prod profiles | A settings file per environment, with a NAT gateway per zone, Multi-AZ, longer backups and deletion protection in prod |
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
