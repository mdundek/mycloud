#!/bin/bash

set -e
set -u

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
	CREATE USER $KEYCLOAK_USER password '$KEYCLOAK_PASS';
	CREATE DATABASE keycloak;
	GRANT ALL PRIVILEGES ON DATABASE keycloak TO $KEYCLOAK_USER;
	CREATE USER $MYCLOUD_USER password '$MYCLOUD_PASS';
	CREATE DATABASE multipaas;
	GRANT ALL PRIVILEGES ON DATABASE multipaas TO $MYCLOUD_USER;
EOSQL
