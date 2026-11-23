-- Recreates the postgres_fdw link from the consumer DB to the master DB.
-- The consumer schema exposes master tables (users, ulb_masters, ulb_ward_masters, ...)
-- as foreign tables, and SWM controllers join them on the pgsql_swm connection.
-- Run as the Postgres superuser while connected to the consumer database, after the restore.
-- Idempotent: safe to re-run.
\set ON_ERROR_STOP on

\getenv master_user DB_USERNAME
\getenv master_password DB_PASSWORD
\getenv master_database DB_DATABASE
\getenv consumer_user DB_CONSUMER_USERNAME

CREATE EXTENSION IF NOT EXISTS postgres_fdw;

DROP SERVER IF EXISTS db_system_server CASCADE;

SELECT format(
    'CREATE SERVER db_system_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host %L, port %L, dbname %L)',
    -- Not 127.0.0.1: the image trusts loopback, and postgres_fdw requires password auth for
    -- non-superusers. The service name resolves to the container's network address (scram-sha-256).
    'db', '5432', :'master_database'
)
\gexec

SELECT format('GRANT USAGE ON FOREIGN SERVER db_system_server TO %I', :'consumer_user')
\gexec

SELECT format(
    'CREATE USER MAPPING FOR %I SERVER db_system_server OPTIONS (user %L, password %L)',
    :'consumer_user', :'master_user', :'master_password'
)
\gexec

-- Import as the consumer app role so it owns the foreign tables.
SELECT format('SET ROLE %I', :'consumer_user')
\gexec

IMPORT FOREIGN SCHEMA public LIMIT TO (
    cache, cache_locks, citizens, failed_jobs, job_batches, jobs, log_otp_requests,
    migrations, mobile_menu_masters, mobile_role_menu_maps, mobile_user_menu_excludes,
    mobile_user_menu_includes, model_logs, module_masters, old_ward_new_ward_maps,
    otp_requests, password_reset_otp_tokens, password_reset_tokens, personal_access_tokens,
    personal_access_tokens_log, role_hierarchies, role_type_mstrs, sessions, ulb_masters,
    ulb_role_permissions, ulb_type_masters, ulb_ward_masters, user_role_maps,
    user_ward_permissions, users, web_menu_masters, web_role_menu_maps,
    web_user_menu_excludes, web_user_menu_includes, workflow_masters, workflow_ulb_role_maps
) FROM SERVER db_system_server INTO public;

RESET ROLE;

SELECT 'foreign tables: ' || count(*) FROM information_schema.foreign_tables WHERE foreign_table_schema = 'public';
