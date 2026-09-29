-- Run from the logged-in mysql client after batches 1-11.
-- Test data is rolled back. This creates then removes one test procedure.
USE movie_seat_booking;
DELIMITER //
CREATE PROCEDURE verify_p1_constraints_batch11()
BEGIN
    DECLARE rejected BOOLEAN DEFAULT FALSE;
    DECLARE passed INT DEFAULT 0;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    -- Positive control: both free B seats must exist before testing.
    IF (SELECT COUNT(*) FROM show_seats
        WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00'
          AND row_label = 'B' AND seat_number IN (1, 2)
          AND status = 'available' AND booking_id IS NULL) <> 2 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: expected free B1 and B2 fixture';
    END IF;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1452 SET rejected = TRUE;
        INSERT INTO screens (theatre_id, screen_name) VALUES (0, 'Invalid theatre');
    END;
    IF NOT rejected THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: orphan screen accepted';
    END IF;
    SET passed = passed + 1, rejected = FALSE;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1062 SET rejected = TRUE;
        INSERT INTO show_seats (screen_id, starts_at, row_label, seat_number)
        VALUES (1, '2026-09-28 10:00:00', 'A', 1);
    END;
    IF NOT rejected THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: duplicate inventory accepted';
    END IF;
    SET passed = passed + 1, rejected = FALSE;

    -- Screen 2 has only row A; B1 belongs to screen 1.
    BEGIN
        DECLARE CONTINUE HANDLER FOR 1452 SET rejected = TRUE;
        INSERT INTO show_seats (screen_id, starts_at, row_label, seat_number)
        VALUES (2, '2026-09-28 11:00:00', 'B', 1);
    END;
    IF NOT rejected THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: wrong-screen seat accepted';
    END IF;
    SET passed = passed + 1, rejected = FALSE;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1452 SET rejected = TRUE;
        UPDATE show_seats SET status = 'sold', booking_id = 1
        WHERE screen_id = 1 AND starts_at = '2026-09-28 14:00:00'
          AND row_label = 'A' AND seat_number = 1;
    END;
    IF NOT rejected THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: wrong-show booking accepted';
    END IF;
    SET passed = passed + 1, rejected = FALSE;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 3819 SET rejected = TRUE;
        UPDATE show_seats SET status = 'sold'
        WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00'
          AND row_label = 'B' AND seat_number = 1;
    END;
    IF NOT rejected THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: sold seat without owner accepted';
    END IF;
    SET passed = passed + 1, rejected = FALSE;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 3819 SET rejected = TRUE;
        UPDATE bookings SET status = 'held', hold_expires_at = NULL WHERE booking_id = 1;
    END;
    IF NOT rejected THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: held booking without expiry accepted';
    END IF;
    SET passed = passed + 1, rejected = FALSE;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 3819 SET rejected = TRUE;
        UPDATE booking_seats SET purchase_price = -1
        WHERE booking_id = 1 AND row_label = 'A' AND seat_number = 1;
    END;
    IF NOT rejected THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: negative item price accepted';
    END IF;
    SET passed = passed + 1, rejected = FALSE;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1062 SET rejected = TRUE;
        INSERT INTO payment_events (
            provider, provider_event_id, booking_id, event_type, amount
        ) VALUES ('demo_provider', 'evt_demo_001', 1, 'payment_succeeded', 400.00);
    END;
    IF NOT rejected THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: duplicate provider event accepted';
    END IF;
    SET passed = passed + 1, rejected = FALSE;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 3819 SET rejected = TRUE;
        UPDATE payment_events SET processed_at = NULL WHERE payment_event_id = 1;
    END;
    IF NOT rejected THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: applied event without timestamp accepted';
    END IF;
    SET passed = passed + 1;

    ROLLBACK;
    SELECT 'PASS: constraint rejection tests' AS result, passed AS tests_passed;
END//
DELIMITER ;
CALL verify_p1_constraints_batch11();
DROP PROCEDURE verify_p1_constraints_batch11;
-- Auto-increment counters can advance despite rollback; fixture rows are unchanged.
