-- Optional administrator installation after booking_api.sql; initially disabled.
USE movie_seat_booking;
SET time_zone = '+05:30';
CREATE INDEX ix_bookings_expiry ON bookings(status, hold_expires_at, booking_id);
DELIMITER //
CREATE PROCEDURE expire_due_bookings()
SQL SECURITY DEFINER
sweep: BEGIN
    DECLARE v_booking INT UNSIGNED;
    DECLARE v_last_expiry DATETIME DEFAULT '1000-01-01';
    DECLARE v_last_booking INT UNSIGNED DEFAULT 0;
    DECLARE v_expiry DATETIME;
    DECLARE v_count INT DEFAULT 0;
    DECLARE v_lock_name VARCHAR(64);
    DECLARE v_acquired INT DEFAULT 0;
    DECLARE v_old_timeout INT DEFAULT @@SESSION.innodb_lock_wait_timeout;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET SESSION innodb_lock_wait_timeout = v_old_timeout;
        IF v_acquired = 1 THEN DO RELEASE_LOCK(v_lock_name); END IF;
        RESIGNAL;
    END;
    SET v_lock_name = CONCAT('expiry:', LEFT(DATABASE(), 57));
    SELECT GET_LOCK(v_lock_name, 0) INTO v_acquired;
    IF COALESCE(v_acquired, 0) <> 1 THEN LEAVE sweep; END IF;
    SET SESSION innodb_lock_wait_timeout = 2;
    sweep_loop: WHILE v_count < 100 DO
        SET v_booking = NULL;
        BEGIN
            DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_booking = NULL;
            SELECT booking_id, hold_expires_at INTO v_booking, v_expiry
            FROM bookings
            WHERE status = 'held' AND hold_expires_at <= SYSDATE()
              AND (hold_expires_at > v_last_expiry
                   OR (hold_expires_at = v_last_expiry AND booking_id > v_last_booking))
            ORDER BY hold_expires_at, booking_id LIMIT 1;
        END;
        IF v_booking IS NULL THEN LEAVE sweep_loop; END IF;
        BEGIN
            -- A busy booking is retried on the next scheduled pass.
            DECLARE CONTINUE HANDLER FOR 1205, 1213 BEGIN END;
            CALL expire_booking(v_booking);
        END;
        SET v_last_expiry = v_expiry, v_last_booking = v_booking;
        SET v_count = v_count + 1;
    END WHILE;
    SET SESSION innodb_lock_wait_timeout = v_old_timeout;
    DO RELEASE_LOCK(v_lock_name);
END//
DELIMITER ;
CREATE EVENT release_expired_holds
ON SCHEDULE EVERY 1 MINUTE
DISABLE
DO CALL expire_due_bookings();
