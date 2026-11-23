-- Marks the migrations whose tables already exist in the pgAdmin-managed schema as "ran",
-- so `php artisan migrate --force` only applies migrations newer than that schema.
-- Run as the Postgres superuser on the MASTER database after restoring a dump. Idempotent.
-- When a new schema dump already contains a later migration's tables, add its name here.
\set ON_ERROR_STOP on

\getenv master_user DB_USERNAME

SELECT format('SET ROLE %I', :'master_user')
\gexec

CREATE TABLE IF NOT EXISTS migrations (
    id serial PRIMARY KEY,
    migration varchar(255) NOT NULL,
    batch integer NOT NULL
);

INSERT INTO migrations (migration, batch)
SELECT m, 1
FROM unnest(ARRAY[
    '0001_01_01_000000_create_users_table',
    '0001_01_01_000001_create_cache_table',
    '0001_01_01_000002_create_jobs_table',
    '2024_07_22_101523_create_cache_locks_table',
    '2024_07_22_101523_create_cache_table',
    '2024_07_22_101523_create_citizen_table',
    '2024_07_22_101523_create_failed_jobs_table',
    '2024_07_22_101523_create_job_batches_table',
    '2024_07_22_101523_create_jobs_table',
    '2024_07_22_101523_create_log_otp_requests_table',
    '2024_07_22_101523_create_old_ward_new_ward_maps_table',
    '2024_07_22_101523_create_otp_requests_table',
    '2024_07_22_101523_create_password_reset_otp_tokens_table',
    '2024_07_22_101523_create_password_reset_tokens_table',
    '2024_07_22_101523_create_personal_access_tokens_log_table',
    '2024_07_22_101523_create_personal_access_tokens_table',
    '2024_07_22_101523_create_role_type_mstrs_table',
    '2024_07_22_101523_create_sessions_table',
    '2024_07_22_101523_create_ulb_masters_table',
    '2024_07_22_101523_create_ulb_type_masters_table',
    '2024_07_22_101523_create_ulb_ward_masters_table',
    '2024_07_22_101523_create_user_role_maps_table',
    '2024_07_22_101523_create_user_ward_permissions_table',
    '2024_07_22_101523_create_users_table',
    '2024_07_22_101523_create_web_menu_masters_table',
    '2024_07_22_101523_create_web_role_menu_maps_table',
    '2024_07_22_101523_create_web_user_menu_excludes_table',
    '2024_07_22_101523_create_web_user_menu_includes_table',
    '2024_07_22_101526_add_foreign_keys_to_ulb_masters_table',
    '2024_07_22_101526_add_foreign_keys_to_ulb_ward_masters_table',
    '2024_07_22_101526_add_foreign_keys_to_user_role_maps_table',
    '2024_07_22_101526_add_foreign_keys_to_users_table'
]) AS m
WHERE NOT EXISTS (SELECT 1 FROM migrations WHERE migration = m);

RESET ROLE;

SELECT 'migrations marked as ran: ' || count(*) FROM migrations;
