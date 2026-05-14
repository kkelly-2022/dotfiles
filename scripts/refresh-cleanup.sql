-- Cleanups required to apply pending migrations on top of the prod snapshot.
-- Runs between `npm run db:refresh` (snapshot restore) and migrations.
-- Add new entries above the existing ones; remove an entry once the migration
-- it unblocks has shipped to prod (so the snapshot itself is clean).

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
