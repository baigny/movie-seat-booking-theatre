-- Optional installation by a database administrator. Assign this role to a new
-- application account with no other privileges. Never grant raw writes to it.
-- Do not grant the internal helper; it is called by the definer routines only.
CREATE ROLE IF NOT EXISTS 'movie_booking_client';
GRANT SELECT ON movie_seat_booking.* TO 'movie_booking_client';
GRANT EXECUTE ON PROCEDURE movie_seat_booking.hold_seats TO 'movie_booking_client';
GRANT EXECUTE ON PROCEDURE movie_seat_booking.confirm_payment TO 'movie_booking_client';
GRANT EXECUTE ON PROCEDURE movie_seat_booking.expire_booking TO 'movie_booking_client';
