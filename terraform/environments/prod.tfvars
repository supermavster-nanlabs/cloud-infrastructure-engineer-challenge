name = "info-api-prod"

# Resilient: a NAT gateway per zone, a standby database, longer backups, and a
# database that cannot be deleted by accident. To destroy prod, set
# db_deletion_protection to false and apply that first.
nat_gateway_per_az       = true
db_multi_az              = true
db_backup_retention_days = 14
db_deletion_protection   = true
db_skip_final_snapshot   = false
