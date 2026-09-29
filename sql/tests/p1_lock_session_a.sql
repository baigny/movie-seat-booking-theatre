-- Run in session A, then leave this session open while running session B.
USE movie_seat_booking;
START TRANSACTION;
SELECT screen_id, starts_at, row_label, seat_number, status, booking_id
FROM show_seats
WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00'
  AND row_label = 'B' AND seat_number = 1
FOR UPDATE;
-- Expect one available seat with NULL booking_id. Leave transaction open.
-- After session B reports its lock timeout, manually execute ROLLBACK here.
