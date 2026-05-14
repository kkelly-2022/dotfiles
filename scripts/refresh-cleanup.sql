-- Cleanups required to apply pending migrations on top of the prod snapshot.
-- Runs between `npm run db:refresh` (snapshot restore) and migrations.
-- Add new entries above the existing ones; remove an entry once the migration
-- it unblocks has shipped to prod (so the snapshot itself is clean).

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
