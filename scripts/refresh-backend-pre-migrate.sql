-- Backend cleanups required to apply pending Prisma migrations on top of the prod snapshot.
-- Runs between backend `npm run db:refresh` (snapshot restore) and Prisma migrations.
-- Add new entries above the existing ones; remove an entry once the migration
-- it unblocks has shipped to prod (so the snapshot itself is clean).

-- 20260629145904_user_noun_relevancy_noun_ref_not_null
-- The refresh script runs before pending Prisma migrations. If the snapshot
-- predates 20260625161936, noun_ref_id does not exist yet, so install a
-- local-only DDL hook that runs as soon as the column is created. If the column
-- already exists, the final SELECT runs it immediately.
CREATE OR REPLACE FUNCTION state_affairs_dev.refresh_backend_backfill_user_noun_relevancy_noun_ref()
RETURNS integer AS $$
DECLARE
  source record;
  changed integer;
  total_changed integer := 0;
BEGIN
  IF to_regclass('state_affairs_dev.user_noun_relevancy') IS NULL
     OR NOT EXISTS (
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'state_affairs_dev'
         AND table_name = 'user_noun_relevancy'
         AND column_name = 'noun_ref_id'
     ) THEN
    RETURN 0;
  END IF;

  FOR source IN
    SELECT * FROM (VALUES
      ('article', 'article'),
      ('bill', 'bill'),
      ('hearing', 'hearing'),
      ('tweets', 'tweets')
    ) AS source_tables(noun_type, table_name)
  LOOP
    IF to_regclass(format('state_affairs_dev.%I', source.table_name)) IS NULL THEN
      CONTINUE;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'state_affairs_dev'
        AND table_name = source.table_name
        AND column_name = 'noun_id'
    ) THEN
      CONTINUE;
    END IF;

    EXECUTE format($sql$
      UPDATE state_affairs_dev.user_noun_relevancy AS unr
      SET noun_ref_id = src.noun_id
      FROM state_affairs_dev.%I AS src
      WHERE unr.noun_ref_id IS NULL
        AND unr.noun_type::text = %L
        AND unr.noun_id = src.id
        AND src.noun_id IS NOT NULL
    $sql$, source.table_name, source.noun_type);

    GET DIAGNOSTICS changed = ROW_COUNT;
    total_changed := total_changed + changed;
    IF changed > 0 THEN
      RAISE NOTICE 'Backfilled user_noun_relevancy.noun_ref_id for % % row(s)', source.noun_type, changed;
    END IF;
  END LOOP;

  DELETE FROM state_affairs_dev.user_noun_relevancy
  WHERE noun_ref_id IS NULL;

  GET DIAGNOSTICS changed = ROW_COUNT;
  total_changed := total_changed + changed;
  IF changed > 0 THEN
    RAISE NOTICE 'Deleted % user_noun_relevancy row(s) still missing noun_ref_id', changed;
  END IF;

  RETURN total_changed;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION state_affairs_dev.refresh_backend_backfill_user_noun_relevancy_noun_ref_after_ddl()
RETURNS event_trigger AS $$
DECLARE
  ddl_command record;
BEGIN
  FOR ddl_command IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF ddl_command.schema_name = 'state_affairs_dev' THEN
      PERFORM state_affairs_dev.refresh_backend_backfill_user_noun_relevancy_noun_ref();
      RETURN;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP EVENT TRIGGER IF EXISTS refresh_backend_backfill_user_noun_relevancy_noun_ref_after_ddl;
CREATE EVENT TRIGGER refresh_backend_backfill_user_noun_relevancy_noun_ref_after_ddl
  ON ddl_command_end
  EXECUTE FUNCTION state_affairs_dev.refresh_backend_backfill_user_noun_relevancy_noun_ref_after_ddl();

SELECT state_affairs_dev.refresh_backend_backfill_user_noun_relevancy_noun_ref();

-- If a prior local migrate run failed while validating this temporary check,
-- clear the partial DDL so Prisma can replay the migration cleanly after the
-- failed migration is resolved/rolled back.
ALTER TABLE IF EXISTS state_affairs_dev.user_noun_relevancy
  DROP CONSTRAINT IF EXISTS user_noun_relevancy_noun_ref_id_not_null;

-- 20260622000001_make_noun_id_not_null
-- Older snapshots can have source rows whose noun_id was never backfilled after
-- the noun table/trigger migration. This cleanup runs immediately when the noun
-- table already exists, and also installs a local-only DDL hook so a fresh
-- refresh can backfill right after 20260612170540_add_noun_table creates the
-- noun table, before 20260622000001_make_noun_id_not_null runs.
CREATE OR REPLACE FUNCTION state_affairs_dev.refresh_backend_backfill_noun_ids()
RETURNS integer AS $$
DECLARE
  source record;
  backfilled integer;
  total_backfilled integer := 0;
BEGIN
  IF to_regclass('state_affairs_dev.noun') IS NULL
     OR to_regtype('state_affairs_dev.noun_kind') IS NULL THEN
    RETURN 0;
  END IF;

  FOR source IN
    SELECT * FROM (VALUES
      ('article', 'article'),
      ('bill', 'bill'),
      ('directories_committees', 'directories_committees'),
      ('directories_legislators', 'directories_legislators'),
      ('directory_people', 'directory_people'),
      ('hearing', 'hearing'),
      ('lobbyist_report', 'lobbyist_report'),
      ('meeting', 'meeting'),
      ('report_360', 'report_360'),
      ('reports', 'reports'),
      ('tracking_list', 'tracking_list'),
      ('tweets', 'tweets')
    ) AS source_tables(table_name, noun_kind)
  LOOP
    IF to_regclass(format('state_affairs_dev.%I', source.table_name)) IS NULL THEN
      CONTINUE;
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'state_affairs_dev'
        AND table_name = source.table_name
        AND column_name = 'noun_id'
    ) THEN
      CONTINUE;
    END IF;

    EXECUTE format($sql$
      WITH source_rows AS (
        SELECT ctid, row_number() OVER (ORDER BY ctid) AS rn
        FROM state_affairs_dev.%I
        WHERE noun_id IS NULL
      ),
      inserted_nouns AS (
        INSERT INTO state_affairs_dev.noun (noun_kind)
        SELECT %L::state_affairs_dev.noun_kind
        FROM source_rows
        RETURNING id
      ),
      numbered_nouns AS (
        SELECT id, row_number() OVER (ORDER BY id) AS rn
        FROM inserted_nouns
      )
      UPDATE state_affairs_dev.%I AS target
      SET noun_id = numbered_nouns.id
      FROM source_rows
      JOIN numbered_nouns USING (rn)
      WHERE target.ctid = source_rows.ctid
    $sql$, source.table_name, source.noun_kind, source.table_name);

    GET DIAGNOSTICS backfilled = ROW_COUNT;
    total_backfilled := total_backfilled + backfilled;
    IF backfilled > 0 THEN
      RAISE NOTICE 'Backfilled %.noun_id for % row(s)', source.table_name, backfilled;
    END IF;
  END LOOP;

  RETURN total_backfilled;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION state_affairs_dev.refresh_backend_backfill_noun_ids_after_ddl()
RETURNS event_trigger AS $$
DECLARE
  ddl_command record;
BEGIN
  -- This event trigger is database-wide, so only run for the backend noun
  -- migration DDL it exists to bridge. Other local schemas (for example
  -- datacore.alembic_version) should not touch state_affairs_dev at all.
  FOR ddl_command IN SELECT * FROM pg_event_trigger_ddl_commands()
  LOOP
    IF ddl_command.schema_name = 'state_affairs_dev'
       AND ddl_command.object_identity IN (
         'state_affairs_dev.noun',
         'state_affairs_dev.article.noun_id',
         'state_affairs_dev.bill.noun_id',
         'state_affairs_dev.directories_committees.noun_id',
         'state_affairs_dev.directories_legislators.noun_id',
         'state_affairs_dev.directory_people.noun_id',
         'state_affairs_dev.hearing.noun_id',
         'state_affairs_dev.lobbyist_report.noun_id',
         'state_affairs_dev.meeting.noun_id',
         'state_affairs_dev.report_360.noun_id',
         'state_affairs_dev.reports.noun_id',
         'state_affairs_dev.tracking_list.noun_id',
         'state_affairs_dev.tweets.noun_id'
       ) THEN
      PERFORM state_affairs_dev.refresh_backend_backfill_noun_ids();
      RETURN;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP EVENT TRIGGER IF EXISTS refresh_backend_backfill_noun_ids_after_ddl;
CREATE EVENT TRIGGER refresh_backend_backfill_noun_ids_after_ddl
  ON ddl_command_end
  EXECUTE FUNCTION state_affairs_dev.refresh_backend_backfill_noun_ids_after_ddl();

SELECT state_affairs_dev.refresh_backend_backfill_noun_ids();

-- Seed: Enterprise Session (session_id = 0)
-- Snapshot lacks this sentinel row; some app code expects it to exist.
INSERT INTO state_affairs_dev.session (
  session_id, state_id, year_start, year_end,
  prefile, sine_die, prior, special,
  session_name, session_title, session_tag,
  import_date, import_hash,
  created_at, updated_at
) VALUES (
  0, 0, 0, 0,
  0, 1, 1, 0,
  'Enterprise Session', 'Enterprise Session', 'Enterprise Session',
  '2025-01-01', 'd7f3a6b8429c415e9d8b2a637c5f74ab',
  '2025-05-15 23:36:56.621', '2025-05-15 23:36:56.621'
) ON CONFLICT (session_id) DO NOTHING;

-- 20260505095920_add_unique_active_newsletter_per_email_type
-- Snapshot has duplicate email_type rows from soft-deleted newsletters.
-- The new unique index only matters for active rows, so drop the rest.
-- newsletter_send_time FKs to newsletter_admininstration with ON DELETE RESTRICT,
-- so child rows must go first.
DELETE FROM state_affairs_dev.newsletter_send_time
WHERE "newsletterAdministrationId" IN (
  SELECT id FROM state_affairs_dev.newsletter_admininstration WHERE active = false
);
DELETE FROM state_affairs_dev.newsletter_admininstration WHERE active = false;
