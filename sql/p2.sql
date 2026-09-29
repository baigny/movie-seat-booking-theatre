-- P2: List shows for a selected theatre and date.
-- Batch 12: two statements (inputs and query). Read-only apart from session variables.
-- Fixed fixture date for repeatable verification; edit inputs to select another day.
SET @theatre_id = 1, @selected_date = DATE('2026-09-28');

SELECT m.title AS movie_title,
       sc.screen_name,
       DATE(sh.starts_at) AS show_date,
       TIME(sh.starts_at) AS show_time
FROM movie_seat_booking.shows AS sh
JOIN movie_seat_booking.movies AS m ON m.movie_id = sh.movie_id
JOIN movie_seat_booking.screens AS sc ON sc.screen_id = sh.screen_id
JOIN movie_seat_booking.theatres AS th ON th.theatre_id = sc.theatre_id
WHERE th.theatre_id = @theatre_id
  AND sh.starts_at >= @selected_date
  AND sh.starts_at < DATE_ADD(@selected_date, INTERVAL 1 DAY)
ORDER BY m.title, sh.starts_at, sh.show_id;
