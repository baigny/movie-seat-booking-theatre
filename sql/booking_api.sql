-- Install after P1, or after migration 001. Top-level calls own transactions.
-- Application accounts get EXECUTE on hold_seats, confirm_payment, expire_booking
-- and SELECT only. No direct DML and no EXECUTE on the internal lock helper.
USE movie_seat_booking;
CREATE VIEW seat_availability AS
SELECT s.screen_id, s.starts_at, s.row_label, s.seat_number, ownership.booking_id,
       CASE WHEN ownership.booking_id IS NULL THEN 'available'
            WHEN ownership.booking_status = 'confirmed' THEN 'sold' ELSE 'held' END AS status,
       ownership.hold_expires_at
FROM show_seats s
LEFT JOIN (
    SELECT a.booking_id, a.row_label, a.seat_number, b.screen_id, b.starts_at,
           b.status AS booking_status, b.hold_expires_at
    FROM seat_allocations a JOIN bookings b ON b.booking_id = a.booking_id
) ownership ON ownership.screen_id = s.screen_id AND ownership.starts_at = s.starts_at
    AND ownership.row_label = s.row_label AND ownership.seat_number = s.seat_number;
DELIMITER //
CREATE PROCEDURE lock_booking_inventory(IN p_booking INT UNSIGNED)
SQL SECURITY DEFINER
BEGIN
    DECLARE done BOOLEAN DEFAULT FALSE;
    DECLARE v_screen INT UNSIGNED;
    DECLARE v_start DATETIME;
    DECLARE v_row VARCHAR(5);
    DECLARE v_num SMALLINT UNSIGNED;
    DECLARE found_seat SMALLINT UNSIGNED;
    DECLARE items CURSOR FOR
        SELECT b.screen_id, b.starts_at, bs.row_label, bs.seat_number
        FROM bookings b JOIN booking_seats bs ON bs.booking_id = b.booking_id
        WHERE b.booking_id = p_booking ORDER BY bs.row_label, bs.seat_number;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    OPEN items;
    item_loop: LOOP
        FETCH items INTO v_screen, v_start, v_row, v_num;
        IF done THEN LEAVE item_loop; END IF;
        SET found_seat = NULL;
        SELECT seat_number INTO found_seat FROM show_seats
        WHERE screen_id = v_screen AND starts_at = v_start
          AND row_label = v_row AND seat_number = v_num FOR UPDATE;
        IF found_seat IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'missing inventory';
        END IF;
    END LOOP;
    CLOSE items;
END//

CREATE PROCEDURE hold_seats(
    IN p_user INT UNSIGNED, IN p_show INT UNSIGNED, IN p_reference CHAR(36),
    IN p_seats JSON, IN p_ttl_seconds INT)
SQL SECURITY DEFINER
BEGIN
    DECLARE done BOOLEAN DEFAULT FALSE;
    DECLARE v_screen INT UNSIGNED;
    DECLARE v_start DATETIME;
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_booking INT UNSIGNED;
    DECLARE v_row VARCHAR(5);
    DECLARE v_num SMALLINT UNSIGNED;
    DECLARE v_found SMALLINT UNSIGNED;
    DECLARE v_count INT;
    DECLARE v_unique INT;
    DECLARE v_now DATETIME;
    DECLARE v_index INT DEFAULT 0;
    DECLARE v_input_row JSON;
    DECLARE v_input_number JSON;
    DECLARE requested CURSOR FOR
        SELECT jt.row_label, jt.seat_number FROM JSON_TABLE(p_seats, '$[*]'
            COLUMNS(row_label VARCHAR(5) PATH '$.row' ERROR ON EMPTY ERROR ON ERROR,
                    seat_number INT PATH '$.number' ERROR ON EMPTY ERROR ON ERROR)) jt
        ORDER BY jt.row_label, jt.seat_number;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    IF p_seats IS NULL OR JSON_TYPE(p_seats) <> 'ARRAY' OR JSON_LENGTH(p_seats) NOT BETWEEN 1 AND 20
       OR p_ttl_seconds IS NULL OR p_ttl_seconds NOT BETWEEN 1 AND 900 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid seats or hold duration';
    END IF;
    -- Validate original JSON before JSON_TABLE can coerce or truncate a value.
    WHILE v_index < JSON_LENGTH(p_seats) DO
        SET v_input_row = JSON_EXTRACT(p_seats, CONCAT('$[', v_index, '].row'));
        SET v_input_number = JSON_EXTRACT(p_seats, CONCAT('$[', v_index, '].number'));
        IF COALESCE(JSON_TYPE(v_input_row), '') <> 'STRING'
           OR CHAR_LENGTH(JSON_UNQUOTE(v_input_row)) NOT BETWEEN 1 AND 5
           OR COALESCE(JSON_TYPE(v_input_number), '') <> 'INTEGER'
           OR CAST(JSON_UNQUOTE(v_input_number) AS DECIMAL(65,0)) NOT BETWEEN 1 AND 65535 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid seat value';
        END IF;
        SET v_index = v_index + 1;
    END WHILE;
    SELECT COUNT(*), COUNT(DISTINCT jt.row_label, jt.seat_number)
    INTO v_count, v_unique FROM JSON_TABLE(p_seats, '$[*]'
        COLUMNS(row_label VARCHAR(5) PATH '$.row' ERROR ON EMPTY ERROR ON ERROR,
                seat_number INT PATH '$.number' ERROR ON EMPTY ERROR ON ERROR)) jt;
    IF v_count <> v_unique THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'duplicate or null requested seat';
    END IF;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SELECT screen_id, starts_at, ticket_price INTO v_screen, v_start, v_price
    FROM shows WHERE show_id = p_show;
    IF v_screen IS NULL OR v_start <= SYSDATE() THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'unknown or started show';
    END IF;
    INSERT INTO bookings (user_id, screen_id, starts_at, booking_reference,
        status, hold_expires_at, total_amount)
    VALUES (p_user, v_screen, v_start, p_reference, 'held',
        DATE_ADD(SYSDATE(), INTERVAL p_ttl_seconds SECOND), v_price * v_count);
    SET v_booking = LAST_INSERT_ID();
    SET done = FALSE;
    OPEN requested;
    seat_loop: LOOP
        FETCH requested INTO v_row, v_num;
        IF done THEN LEAVE seat_loop; END IF;
        SET v_found = NULL;
        SELECT seat_number INTO v_found FROM show_seats
        WHERE screen_id = v_screen AND starts_at = v_start
          AND row_label = v_row AND seat_number = v_num FOR UPDATE;
        IF v_found IS NULL THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'seat does not belong to show';
        END IF;
        -- Inventory mutex is held; RC sees any winner committed while waiting.
        IF EXISTS (SELECT 1 FROM seat_allocations a JOIN bookings b
            ON b.booking_id = a.booking_id WHERE b.screen_id = v_screen
            AND b.starts_at = v_start AND a.row_label = v_row AND a.seat_number = v_num) THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'seat unavailable';
        END IF;
        INSERT INTO seat_allocations VALUES (v_booking, v_row, v_num);
        INSERT INTO booking_seats VALUES (v_booking, v_row, v_num, v_price);
    END LOOP;
    CLOSE requested;
    SET v_now = SYSDATE();
    IF v_start <= v_now THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'show started during wait';
    END IF;
    UPDATE bookings SET created_at = v_now,
        hold_expires_at = DATE_ADD(v_now, INTERVAL p_ttl_seconds SECOND)
    WHERE booking_id = v_booking;
    COMMIT;
    SELECT v_booking AS booking_id, 'held' AS outcome;
END//

CREATE PROCEDURE expire_booking(IN p_booking INT UNSIGNED)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_expiry DATETIME;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SELECT status, hold_expires_at INTO v_status, v_expiry
    FROM bookings WHERE booking_id = p_booking FOR UPDATE;
    IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'unknown booking'; END IF;
    CALL lock_booking_inventory(p_booking);
    IF v_status = 'held' AND v_expiry <= SYSDATE() THEN
        DELETE FROM seat_allocations WHERE booking_id = p_booking;
        UPDATE bookings SET status = 'expired' WHERE booking_id = p_booking;
        SET v_status = 'expired';
    END IF;
    COMMIT;
    SELECT v_status AS outcome;
END//

CREATE PROCEDURE confirm_payment(IN p_booking INT UNSIGNED,
    IN p_provider VARCHAR(50), IN p_event VARCHAR(191), IN p_amount DECIMAL(10,2))
SQL SECURITY DEFINER
BEGIN
    DECLARE v_status VARCHAR(20);
    DECLARE v_expiry DATETIME;
    DECLARE v_total DECIMAL(10,2);
    DECLARE v_event_booking INT UNSIGNED;
    DECLARE v_event_amount DECIMAL(10,2);
    DECLARE v_event_status VARCHAR(20);
    DECLARE v_event_type VARCHAR(30);
    DECLARE v_items INT;
    DECLARE v_allocations INT;
    DECLARE v_sum DECIMAL(10,2);
    DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;
    IF p_amount IS NULL OR p_amount < 0 OR p_provider IS NULL OR p_provider = ''
       OR p_event IS NULL OR p_event = '' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'invalid payment';
    END IF;
    SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
    START TRANSACTION;
    SELECT status, hold_expires_at, total_amount INTO v_status, v_expiry, v_total
    FROM bookings WHERE booking_id = p_booking FOR UPDATE;
    IF v_status IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'unknown booking'; END IF;
    CALL lock_booking_inventory(p_booking);
    INSERT INTO payment_events (provider, provider_event_id, booking_id, event_type, amount)
    VALUES (p_provider, p_event, p_booking, 'payment_succeeded', p_amount)
    ON DUPLICATE KEY UPDATE payment_event_id = payment_event_id;
    SELECT booking_id, amount, processing_status, event_type
    INTO v_event_booking, v_event_amount, v_event_status, v_event_type
    FROM payment_events WHERE provider = p_provider AND provider_event_id = p_event FOR UPDATE;
    IF v_event_booking <> p_booking OR v_event_amount <> p_amount OR v_event_type <> 'payment_succeeded' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'event payload mismatch';
    END IF;
    IF v_event_status = 'pending' THEN
        SELECT COUNT(*), COALESCE(SUM(purchase_price), 0) INTO v_items, v_sum
        FROM booking_seats WHERE booking_id = p_booking;
        SELECT COUNT(*) INTO v_allocations FROM seat_allocations WHERE booking_id = p_booking;
        IF v_status = 'held' AND v_expiry > SYSDATE() AND v_total = p_amount
           AND v_sum = v_total AND v_items > 0 AND v_allocations = v_items
           AND NOT EXISTS (SELECT 1 FROM booking_seats bs LEFT JOIN seat_allocations a
               ON a.booking_id = bs.booking_id AND a.row_label = bs.row_label
               AND a.seat_number = bs.seat_number
               WHERE bs.booking_id = p_booking AND a.booking_id IS NULL) THEN
            UPDATE bookings SET status = 'confirmed' WHERE booking_id = p_booking;
            SET v_event_status = 'applied';
        ELSE
            IF v_status = 'held' AND v_expiry <= SYSDATE() THEN
                DELETE FROM seat_allocations WHERE booking_id = p_booking;
                UPDATE bookings SET status = 'expired' WHERE booking_id = p_booking;
            END IF;
            SET v_event_status = 'refund_required';
        END IF;
        UPDATE payment_events SET processing_status = v_event_status, processed_at = SYSDATE()
        WHERE provider = p_provider AND provider_event_id = p_event;
    END IF;
    COMMIT;
    SELECT v_event_status AS outcome;
END//
DELIMITER ;
