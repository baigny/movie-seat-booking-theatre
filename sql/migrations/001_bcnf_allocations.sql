-- Run ONCE on the old schema, with application writes stopped and a backup.
-- MySQL DDL commits implicitly. Stop on the first error; do not use --force.
-- Existing sample/user rows are preserved; install booking_api.sql afterward.
USE movie_seat_booking;
DELIMITER //
CREATE PROCEDURE assert_bcnf_migration_ready()
BEGIN
    IF EXISTS (SELECT 1 FROM show_seats s LEFT JOIN bookings b ON b.booking_id=s.booking_id
       WHERE (s.status='held' AND (b.status<>'held' OR b.booking_id IS NULL))
          OR (s.status='sold' AND (b.status<>'confirmed' OR b.booking_id IS NULL))) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'migration stopped: inventory/booking status mismatch';
    END IF;
    IF EXISTS (SELECT 1 FROM show_seats s LEFT JOIN booking_seats i
       ON i.booking_id=s.booking_id AND i.row_label=s.row_label AND i.seat_number=s.seat_number
       WHERE s.booking_id IS NOT NULL AND i.booking_id IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'migration stopped: allocation lacks historical item';
    END IF;
    IF EXISTS (SELECT 1 FROM booking_seats i JOIN bookings b ON b.booking_id=i.booking_id
       LEFT JOIN show_seats s ON s.screen_id=b.screen_id AND s.starts_at=b.starts_at
        AND s.row_label=i.row_label AND s.seat_number=i.seat_number AND s.booking_id=i.booking_id
       WHERE b.status IN ('held','confirmed') AND s.booking_id IS NULL) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'migration stopped: active booking lacks allocation';
    END IF;
END//
DELIMITER ;
CALL assert_bcnf_migration_ready();
DROP PROCEDURE assert_bcnf_migration_ready;
CREATE TABLE seat_allocations (
    booking_id INT UNSIGNED NOT NULL,
    row_label VARCHAR(5) NOT NULL,
    seat_number SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (booking_id, row_label, seat_number),
    CONSTRAINT chk_allocations_number CHECK (seat_number > 0),
    CONSTRAINT fk_allocations_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;
INSERT INTO seat_allocations (booking_id, row_label, seat_number)
SELECT booking_id, row_label, seat_number FROM show_seats WHERE booking_id IS NOT NULL;
ALTER TABLE show_seats
    DROP FOREIGN KEY fk_show_seats_booking,
    DROP CHECK chk_show_seats_allocation,
    DROP INDEX ix_show_seats_booking,
    DROP INDEX ix_show_seats_status,
    DROP COLUMN booking_id,
    DROP COLUMN status;
ALTER TABLE bookings DROP INDEX uq_bookings_id_show;
