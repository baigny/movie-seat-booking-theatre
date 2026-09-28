-- P1: MySQL schema and sample data.
-- Target: MySQL 8.0.16+ with InnoDB.
-- Batch 1: create and select the project database.
-- Tables and sample data will be added in subsequent batches.

CREATE DATABASE IF NOT EXISTS movie_seat_booking
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE movie_seat_booking;

-- Batch 2: theatres and their screens.
CREATE TABLE theatres (
    theatre_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    theatre_name VARCHAR(150) NOT NULL,
    address VARCHAR(500) NOT NULL,
    PRIMARY KEY (theatre_id)
) ENGINE=InnoDB;

CREATE TABLE screens (
    screen_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    theatre_id INT UNSIGNED NOT NULL,
    screen_name VARCHAR(50) NOT NULL,
    PRIMARY KEY (screen_id),
    CONSTRAINT uq_screens_theatre_name UNIQUE (theatre_id, screen_name),
    CONSTRAINT fk_screens_theatre FOREIGN KEY (theatre_id)
        REFERENCES theatres (theatre_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;

-- Batch 3: fictional sample theatres and screens (run once).
INSERT INTO theatres (theatre_id, theatre_name, address) VALUES
    (1, 'Starlight Cinema', '10 Sample Road, Bengaluru, Karnataka, India'),
    (2, 'Moonlight Cinema', '20 Example Road, Chennai, Tamil Nadu, India');

INSERT INTO screens (screen_id, theatre_id, screen_name) VALUES
    (1, 1, 'Screen 1'),
    (2, 1, 'Screen 2'),
    (3, 2, 'Screen 1');

-- Batch 4: movie catalogue and physical seats.
CREATE TABLE movies (
    movie_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    title VARCHAR(200) NOT NULL,
    duration_minutes SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (movie_id),
    CONSTRAINT chk_movies_duration CHECK (duration_minutes > 0)
) ENGINE=InnoDB;

CREATE TABLE seats (
    seat_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    screen_id INT UNSIGNED NOT NULL,
    row_label VARCHAR(5) NOT NULL,
    seat_number SMALLINT UNSIGNED NOT NULL,
    PRIMARY KEY (seat_id),
    CONSTRAINT uq_seats_position UNIQUE (screen_id, row_label, seat_number),
    CONSTRAINT chk_seats_number CHECK (seat_number > 0),
    CONSTRAINT fk_seats_screen FOREIGN KEY (screen_id)
        REFERENCES screens (screen_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;

-- Batch 5: fictional movies and a small demonstration seating layout.
INSERT INTO movies (movie_id, title, duration_minutes) VALUES
    (1, 'Journey to the Stars', 120),
    (2, 'The Last Train', 105),
    (3, 'Ocean of Dreams', 135);

INSERT INTO seats (seat_id, screen_id, row_label, seat_number) VALUES
    (1, 1, 'A', 1),
    (2, 1, 'A', 2),
    (3, 1, 'B', 1),
    (4, 1, 'B', 2),
    (5, 2, 'A', 1),
    (6, 2, 'A', 2),
    (7, 3, 'A', 1),
    (8, 3, 'A', 2);

-- Batch 6: scheduled shows and booking customers.
CREATE TABLE shows (
    show_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    movie_id INT UNSIGNED NOT NULL,
    screen_id INT UNSIGNED NOT NULL,
    starts_at DATETIME NOT NULL,
    ticket_price DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (show_id),
    CONSTRAINT uq_shows_screen_start UNIQUE (screen_id, starts_at),
    CONSTRAINT chk_shows_price CHECK (ticket_price >= 0),
    CONSTRAINT fk_shows_movie FOREIGN KEY (movie_id)
        REFERENCES movies (movie_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_shows_screen FOREIGN KEY (screen_id)
        REFERENCES screens (screen_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE users (
    user_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(254) NOT NULL,
    PRIMARY KEY (user_id),
    CONSTRAINT uq_users_email UNIQUE (email)
) ENGINE=InnoDB;

-- Batch 7: fixed-date sample shows and fictional customers (run once).
INSERT INTO shows (show_id, movie_id, screen_id, starts_at, ticket_price) VALUES
    (1, 1, 1, '2026-09-28 10:00:00', 200.00),
    (2, 1, 1, '2026-09-28 14:00:00', 220.00),
    (3, 2, 2, '2026-09-28 11:00:00', 180.00),
    (4, 3, 3, '2026-09-28 10:00:00', 250.00),
    (5, 2, 1, '2026-09-29 10:00:00', 200.00),
    (6, 3, 1, '2026-09-30 10:00:00', 240.00),
    (7, 1, 1, '2026-10-01 10:00:00', 200.00),
    (8, 2, 1, '2026-10-02 10:00:00', 200.00),
    (9, 3, 1, '2026-10-03 10:00:00', 260.00),
    (10, 1, 1, '2026-10-04 10:00:00', 220.00);

INSERT INTO users (user_id, full_name, email) VALUES
    (1, 'Asha Rao', 'asha@example.com'),
    (2, 'Ravi Kumar', 'ravi@example.com');

-- Batch 8: bookings and per-show seat inventory.
CREATE TABLE bookings (
    booking_id INT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id INT UNSIGNED NOT NULL,
    screen_id INT UNSIGNED NOT NULL,
    starts_at DATETIME NOT NULL,
    booking_reference CHAR(36) NOT NULL,
    status ENUM('held', 'confirmed', 'expired', 'cancelled', 'payment_failed')
        NOT NULL DEFAULT 'held',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    hold_expires_at DATETIME NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (booking_id),
    CONSTRAINT uq_bookings_reference UNIQUE (booking_reference),
    CONSTRAINT uq_bookings_id_show UNIQUE (booking_id, screen_id, starts_at),
    KEY ix_bookings_user_created (user_id, created_at),
    CONSTRAINT chk_bookings_amount CHECK (total_amount >= 0),
    CONSTRAINT chk_bookings_hold_expiry CHECK (
        status <> 'held' OR hold_expires_at IS NOT NULL
    ),
    CONSTRAINT fk_bookings_user FOREIGN KEY (user_id)
        REFERENCES users (user_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_bookings_show FOREIGN KEY (screen_id, starts_at)
        REFERENCES shows (screen_id, starts_at)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE show_seats (
    screen_id INT UNSIGNED NOT NULL,
    starts_at DATETIME NOT NULL,
    row_label VARCHAR(5) NOT NULL,
    seat_number SMALLINT UNSIGNED NOT NULL,
    status ENUM('available', 'held', 'sold') NOT NULL DEFAULT 'available',
    booking_id INT UNSIGNED NULL,
    PRIMARY KEY (screen_id, starts_at, row_label, seat_number),
    KEY ix_show_seats_status (screen_id, starts_at, status, row_label, seat_number),
    KEY ix_show_seats_booking (booking_id, screen_id, starts_at),
    CONSTRAINT chk_show_seats_allocation CHECK (
        (status = 'available' AND booking_id IS NULL)
        OR (status IN ('held', 'sold') AND booking_id IS NOT NULL)
    ),
    CONSTRAINT fk_show_seats_show FOREIGN KEY (screen_id, starts_at)
        REFERENCES shows (screen_id, starts_at)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_show_seats_seat FOREIGN KEY (screen_id, row_label, seat_number)
        REFERENCES seats (screen_id, row_label, seat_number)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_show_seats_booking FOREIGN KEY (booking_id, screen_id, starts_at)
        REFERENCES bookings (booking_id, screen_id, starts_at)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;

-- Batch 9: historical booking items and payment event processing.
CREATE TABLE booking_seats (
    booking_id INT UNSIGNED NOT NULL,
    row_label VARCHAR(5) NOT NULL,
    seat_number SMALLINT UNSIGNED NOT NULL,
    purchase_price DECIMAL(10,2) NOT NULL,
    PRIMARY KEY (booking_id, row_label, seat_number),
    CONSTRAINT chk_booking_seats_number CHECK (seat_number > 0),
    CONSTRAINT chk_booking_seats_price CHECK (purchase_price >= 0),
    CONSTRAINT fk_booking_seats_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;

CREATE TABLE payment_events (
    payment_event_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    provider VARCHAR(50) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    provider_event_id VARCHAR(191) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    booking_id INT UNSIGNED NOT NULL,
    event_type ENUM('payment_succeeded', 'payment_failed', 'refund_succeeded')
        NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    processing_status ENUM('pending', 'applied', 'ignored', 'refund_required')
        NOT NULL DEFAULT 'pending',
    received_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    processed_at DATETIME NULL,
    PRIMARY KEY (payment_event_id),
    CONSTRAINT uq_payment_events_provider_event UNIQUE (provider, provider_event_id),
    KEY ix_payment_events_booking (booking_id, received_at),
    CONSTRAINT chk_payment_events_amount CHECK (amount >= 0),
    CONSTRAINT chk_payment_events_processed CHECK (
        (processing_status = 'pending' AND processed_at IS NULL)
        OR (processing_status <> 'pending' AND processed_at IS NOT NULL)
    ),
    CONSTRAINT fk_payment_events_booking FOREIGN KEY (booking_id)
        REFERENCES bookings (booking_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB;
