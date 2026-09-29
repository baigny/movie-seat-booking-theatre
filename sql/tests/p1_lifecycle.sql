-- Diagnostic protocol examples against the batch 11 fixture.
-- Run ROLLBACK in the earlier locking-test session A before sourcing this file.
-- All fixture writes roll back; auto-increment counters may advance.
USE movie_seat_booking;
DELIMITER //
CREATE PROCEDURE verify_p1_lifecycle_batch11()
BEGIN
    DECLARE old_booking INT UNSIGNED;
    DECLARE new_booking INT UNSIGNED;
    DECLARE affected INT;
    DECLARE duplicate_event BOOLEAN DEFAULT FALSE;
    DECLARE passed INT DEFAULT 0;
    DECLARE seat_status VARCHAR(20);
    DECLARE seat_owner INT UNSIGNED;
    DECLARE event_key VARCHAR(191);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    SET event_key = CONCAT('test_', UUID());
    -- These new bookings are private to this transaction. In a live operation,
    -- lock existing booking rows first, then inventory in primary-key order.
    INSERT INTO bookings (user_id, screen_id, starts_at, booking_reference,
        status, hold_expires_at, total_amount)
    VALUES (1, 1, '2026-09-28 10:00:00', UUID(), 'held',
        DATE_SUB(NOW(), INTERVAL 1 MINUTE), 200.00);
    SET old_booking = LAST_INSERT_ID();
    INSERT INTO bookings (user_id, screen_id, starts_at, booking_reference,
        status, hold_expires_at, total_amount)
    VALUES (2, 1, '2026-09-28 10:00:00', UUID(), 'held',
        DATE_ADD(NOW(), INTERVAL 10 MINUTE), 200.00);
    SET new_booking = LAST_INSERT_ID();

    SELECT status, booking_id INTO seat_status, seat_owner
    FROM show_seats
    WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00'
      AND row_label = 'B' AND seat_number = 1 FOR UPDATE;
    IF seat_status <> 'available' OR seat_owner IS NOT NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: B1 must start available';
    END IF;
    -- Construct an already-expired hold to exercise cleanup, not a live sale.
    UPDATE show_seats SET status = 'held', booking_id = old_booking
    WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00'
      AND row_label = 'B' AND seat_number = 1;
    UPDATE bookings SET status = 'expired'
    WHERE booking_id = old_booking AND status = 'held'
      AND hold_expires_at <= NOW();
    SET affected = ROW_COUNT();
    IF affected <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: expired hold not marked expired';
    END IF;
    UPDATE show_seats SET status = 'available', booking_id = NULL
    WHERE booking_id = old_booking AND status = 'held';
    SET affected = ROW_COUNT();
    IF affected <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: expired seat not released';
    END IF;
    SET passed = passed + 1;

    UPDATE show_seats SET status = 'held', booking_id = new_booking
    WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00'
      AND row_label = 'B' AND seat_number = 1
      AND status = 'available' AND booking_id IS NULL;
    SET affected = ROW_COUNT();
    IF affected <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: released seat not reassigned';
    END IF;
    SET passed = passed + 1;

    -- A late success must match both unexpired booking and current ownership.
    UPDATE show_seats AS ss JOIN bookings AS b ON b.booking_id = ss.booking_id
        AND b.screen_id = ss.screen_id AND b.starts_at = ss.starts_at
    SET ss.status = 'sold'
    WHERE b.booking_id = old_booking AND b.status = 'held'
      AND b.hold_expires_at > NOW() AND ss.status = 'held';
    SET affected = ROW_COUNT();
    IF affected <> 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: stale confirmation changed inventory';
    END IF;
    IF (SELECT COUNT(*) FROM show_seats WHERE screen_id = 1
        AND starts_at = '2026-09-28 10:00:00' AND row_label = 'B'
        AND seat_number = 1 AND status = 'held' AND booking_id = new_booking) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: new owner was displaced';
    END IF;
    INSERT INTO payment_events (provider, provider_event_id, booking_id,
        event_type, amount, processing_status, processed_at)
    VALUES ('test_provider', CONCAT(event_key, '_late'), old_booking,
        'payment_succeeded', 200.00, 'refund_required', NOW());
    IF (SELECT status FROM bookings WHERE booking_id = old_booking) <> 'expired' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: stale booking was confirmed';
    END IF;
    SET passed = passed + 1;

    INSERT INTO payment_events (provider, provider_event_id, booking_id,
        event_type, amount) VALUES
        ('test_provider', event_key, new_booking, 'payment_succeeded', 200.00);
    -- Locks remain held. Validate amount and deadline before changing inventory.
    UPDATE show_seats AS ss JOIN bookings AS b ON b.booking_id = ss.booking_id
        AND b.screen_id = ss.screen_id AND b.starts_at = ss.starts_at
    SET ss.status = 'sold'
    WHERE b.booking_id = new_booking AND b.status = 'held'
      AND b.hold_expires_at > NOW() AND b.total_amount = 200.00
      AND ss.status = 'held';
    SET affected = ROW_COUNT();
    IF affected <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: current owner confirmation failed';
    END IF;
    UPDATE bookings SET status = 'confirmed'
    WHERE booking_id = new_booking AND status = 'held' AND hold_expires_at > NOW();
    SET affected = ROW_COUNT();
    IF affected <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: booking confirmation failed';
    END IF;
    UPDATE payment_events SET processing_status = 'applied', processed_at = NOW()
    WHERE provider = 'test_provider' AND provider_event_id = event_key;
    SET passed = passed + 1;

    BEGIN
        DECLARE CONTINUE HANDLER FOR 1062 SET duplicate_event = TRUE;
        INSERT INTO payment_events (provider, provider_event_id, booking_id,
            event_type, amount) VALUES
            ('test_provider', event_key, new_booking, 'payment_succeeded', 200.00);
    END;
    IF NOT duplicate_event THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: duplicate payment accepted';
    END IF;
    IF (SELECT COUNT(*) FROM payment_events WHERE provider = 'test_provider'
        AND provider_event_id = event_key AND processing_status = 'applied') <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: duplicate changed applied event';
    END IF;
    SET passed = passed + 1;

    -- Repeated confirmation is a no-op even after the first event applied.
    UPDATE bookings SET status = 'confirmed'
    WHERE booking_id = new_booking AND status = 'held' AND hold_expires_at > NOW();
    SET affected = ROW_COUNT();
    IF affected <> 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: repeated confirmation changed booking';
    END IF;
    UPDATE show_seats SET status = 'sold'
    WHERE booking_id = new_booking AND status = 'held';
    SET affected = ROW_COUNT();
    IF affected <> 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: repeated confirmation changed inventory';
    END IF;
    IF (SELECT COUNT(*) FROM show_seats WHERE screen_id = 1
        AND starts_at = '2026-09-28 10:00:00' AND row_label = 'B'
        AND seat_number = 1 AND status = 'sold' AND booking_id = new_booking) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: final sold ownership incorrect';
    END IF;
    SET passed = passed + 1;
    ROLLBACK;
    SELECT 'PASS: lifecycle protocol tests' AS result, passed AS tests_passed;
END//
DELIMITER ;
CALL verify_p1_lifecycle_batch11();
DROP PROCEDURE verify_p1_lifecycle_batch11;
SELECT status, booking_id FROM show_seats
WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00'
  AND row_label = 'B' AND seat_number = 1;
-- Expect available / NULL after rollback.
