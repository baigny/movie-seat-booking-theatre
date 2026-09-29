-- Template: use only through prepare_race_run.ps1's generated script.
SET @race_previous_timeout = @@SESSION.innodb_lock_wait_timeout;
SET SESSION innodb_lock_wait_timeout = 120;
CALL verify_overlapping_claim_and_payment();
SET SESSION innodb_lock_wait_timeout = @race_previous_timeout;
SELECT row_label, seat_number, status, booking_id FROM show_seats
WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00' AND row_label = 'B'
ORDER BY seat_number;
