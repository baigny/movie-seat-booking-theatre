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
