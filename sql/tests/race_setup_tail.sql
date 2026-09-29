-- Executed only in a newly generated race-test schema.
INSERT INTO bookings (booking_id, user_id, screen_id, starts_at,
    booking_reference, status, hold_expires_at, total_amount)
VALUES (2, 2, 1, '2026-09-28 10:00:00', UUID(), 'held',
    DATE_ADD(NOW(), INTERVAL 1 DAY), 400.00);
DELIMITER //
CREATE PROCEDURE verify_overlapping_claim_and_payment()
BEGIN
    DECLARE changed_rows INT;
    DECLARE duplicate_event BOOLEAN DEFAULT FALSE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    START TRANSACTION;
    -- PK order: B1 first, then B2. A holds B1, so the first update must wait.
    UPDATE show_seats SET status = 'held', booking_id = 2
    WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00'
      AND row_label = 'B' AND seat_number = 1
      AND status = 'available' AND booking_id IS NULL;
    SET changed_rows = ROW_COUNT();
    UPDATE show_seats SET status = 'held', booking_id = 2
    WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00'
      AND row_label = 'B' AND seat_number = 2
      AND status = 'available' AND booking_id IS NULL;
    SET changed_rows = changed_rows + ROW_COUNT();
    -- Winner A committed B1; B can acquire only B2, so reject the whole request.
    IF changed_rows <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: expected exactly one provisional seat';
    END IF;
    ROLLBACK;
    IF (SELECT COUNT(*) FROM show_seats WHERE screen_id = 1
        AND starts_at = '2026-09-28 10:00:00' AND row_label = 'B'
        AND seat_number = 1 AND status = 'sold' AND booking_id = 1) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: winner ownership not retained';
    END IF;
    IF (SELECT COUNT(*) FROM show_seats WHERE screen_id = 1
        AND starts_at = '2026-09-28 10:00:00' AND row_label = 'B'
        AND seat_number = 2 AND status = 'available' AND booking_id IS NULL) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: partial claim was not rolled back';
    END IF;
    SELECT 'PASS: committed winner retained; partial two-seat claim rolled back' AS result;

    START TRANSACTION;
    BEGIN
        DECLARE CONTINUE HANDLER FOR 1062 SET duplicate_event = TRUE;
        INSERT INTO payment_events (provider, provider_event_id, booking_id,
            event_type, amount)
        VALUES ('race_provider', 'race_event_001', 1, 'payment_succeeded', 200.00);
    END;
    IF NOT duplicate_event THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: duplicate event was accepted';
    END IF;
    ROLLBACK;
    IF (SELECT COUNT(*) FROM payment_events WHERE provider = 'race_provider'
        AND provider_event_id = 'race_event_001' AND processing_status = 'applied'
        AND amount = 200.00 AND booking_id = 1) <> 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'FAIL: original event was changed';
    END IF;
    SELECT 'PASS: committed payment event retained once' AS result;
END//
DELIMITER ;
