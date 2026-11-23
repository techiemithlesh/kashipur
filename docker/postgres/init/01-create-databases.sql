\set ON_ERROR_STOP on

\getenv master_user DB_USERNAME
\getenv master_password DB_PASSWORD
\getenv master_database DB_DATABASE
\getenv consumer_user DB_CONSUMER_USERNAME
\getenv consumer_password DB_CONSUMER_PASSWORD
\getenv consumer_database DB_CONSUMER_DATABASE

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'master_user', :'master_password')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = :'master_user'
)
\gexec

SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'consumer_user', :'consumer_password')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = :'consumer_user'
)
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'master_database', :'master_user')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = :'master_database'
)
\gexec

SELECT format('CREATE DATABASE %I OWNER %I', :'consumer_database', :'consumer_user')
WHERE NOT EXISTS (
    SELECT 1 FROM pg_database WHERE datname = :'consumer_database'
)
\gexec

SELECT format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', :'master_database')
\gexec

SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'master_database', :'master_user')
\gexec

SELECT format('REVOKE CONNECT ON DATABASE %I FROM PUBLIC', :'consumer_database')
\gexec

SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'consumer_database', :'consumer_user')
\gexec
