-- Remove transient local-only hooks/functions installed by refresh-backend-pre-migrate.sql.
-- Run after backend Prisma migrations, before other schemas (for example datacore)
-- run their own migrations in the same local database.
DROP EVENT TRIGGER IF EXISTS refresh_backend_backfill_user_noun_relevancy_noun_ref_after_ddl;
DROP FUNCTION IF EXISTS state_affairs_dev.refresh_backend_backfill_user_noun_relevancy_noun_ref_after_ddl();
DROP FUNCTION IF EXISTS state_affairs_dev.refresh_backend_backfill_user_noun_relevancy_noun_ref();

DROP EVENT TRIGGER IF EXISTS refresh_backend_backfill_noun_ids_after_ddl;
DROP FUNCTION IF EXISTS state_affairs_dev.refresh_backend_backfill_noun_ids_after_ddl();
DROP FUNCTION IF EXISTS state_affairs_dev.refresh_backend_backfill_noun_ids();

-- Clean up the previous generic names if they exist from an older shell/script run.
DROP EVENT TRIGGER IF EXISTS refresh_cleanup_backfill_noun_ids_after_ddl;
DROP FUNCTION IF EXISTS state_affairs_dev.refresh_cleanup_backfill_noun_ids_after_ddl();
DROP FUNCTION IF EXISTS state_affairs_dev.refresh_cleanup_backfill_noun_ids();
