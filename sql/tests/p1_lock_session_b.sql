-- Run only while session A holds its transaction open on B1.
USE movie_seat_booking;
SET @previous_lock_wait_timeout = @@SESSION.innodb_lock_wait_timeout;
SET SESSION innodb_lock_wait_timeout = 3;
START TRANSACTION;
UPDATE show_seats SET status = 'sold', booking_id = 1
WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00'
  AND row_label = 'B' AND seat_number = 1
  AND status = 'available' AND booking_id IS NULL;
-- EXPECT ERROR 1205 (lock wait timeout). Success means the test was not coordinated.
-- This is a lock exclusion probe, not a complete booking transaction.
ROLLBACK;
SET SESSION innodb_lock_wait_timeout = @previous_lock_wait_timeout;
SELECT status, booking_id FROM show_seats
WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00'
  AND row_label = 'B' AND seat_number = 1;
-- Expect available / NULL. Roll back session A after this script finishes.
