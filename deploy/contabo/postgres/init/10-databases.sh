#!/bin/sh
# First-initialisation only (runs when the pg-data volume is empty).
# Creates non-superuser owners and the three databases (spec D4):
#   stellarbyte          app (Prisma), owner stellarbyte
#   temporal             Temporal persistence, owner temporal
#   temporal_visibility  Temporal SQL visibility (D5, no Elasticsearch), owner temporal
# Passwords come from the container env; they are never written to disk here.
set -eu

: "${STELLARBYTE_DB_PASSWORD:?missing}"
: "${TEMPORAL_DB_PASSWORD:?missing}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
  -v app_pw="$STELLARBYTE_DB_PASSWORD" -v temporal_pw="$TEMPORAL_DB_PASSWORD" <<'SQL'
CREATE ROLE stellarbyte LOGIN PASSWORD :'app_pw';
CREATE ROLE temporal LOGIN PASSWORD :'temporal_pw';
CREATE DATABASE stellarbyte OWNER stellarbyte;
CREATE DATABASE temporal OWNER temporal;
CREATE DATABASE temporal_visibility OWNER temporal;
REVOKE ALL ON DATABASE stellarbyte FROM PUBLIC;
REVOKE ALL ON DATABASE temporal FROM PUBLIC;
REVOKE ALL ON DATABASE temporal_visibility FROM PUBLIC;
SQL

# Temporal SQL visibility schema uses btree_gin; create it as superuser up front
# so the schema tool does not depend on trusted-extension rules.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname temporal_visibility \
  -c 'CREATE EXTENSION IF NOT EXISTS btree_gin;'
