name = "info-api-dev"

# Cheap and disposable: one shared NAT gateway, no standby, nothing blocking teardown.
nat_gateway_per_az       = false
db_multi_az              = false
db_backup_retention_days = 7
db_deletion_protection   = false
db_skip_final_snapshot   = true
