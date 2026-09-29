# Movie Seat Booking Theatre — P1 and P2 Plan

Repository: https://github.com/baigny/movie-seat-booking-theatre

## Goal and submission

Submit a GitHub pull request containing a Markdown document listing all tables,
attributes, relationships, and example rows, plus directly executable MySQL SQL
for P1 and P2. This submission does not include a frontend, backend application,
Redis service, or load-test implementation.

## Deliverables

- `README.md`: schema documentation, relationships, sample rows, normalization
  reasoning, concurrency strategy, execution instructions, and references.
- `sql/p1.sql`: table creation, constraints, indexes, and sample INSERT statements.
- `sql/p2.sql`: showtime query using MySQL variables for theatre ID and date.

## P1: Database design

| Table | Purpose |
| --- | --- |
| theatres | Theatre names and addresses |
| screens | Screens belonging to each theatre |
| seats | Physical seats within each screen |
| movies | Movie titles and durations |
| shows | Movie, screen, and scheduled start time |
| users | Customers who book tickets |
| show_seats | Valid physical inventory for each show; no owner/status redundancy |
| seat_allocations | BCNF current ownership; show derived through bookings |
| bookings | Customer bookings, status, and hold expiry |
| booking_seats | Seats associated with each booking |
| payment_events | Payment event identifiers and processing outcomes |

1. Define attributes, data types, primary keys, foreign keys, unique constraints,
   and indexes for every table.
2. Distinguish physical seats from seat availability for a particular show.
   Enforce one inventory row per show and seat. Validate that each seat belongs
   to the screen hosting the show.
3. Document candidate keys and functional dependencies. Explain 1NF, 2NF, 3NF,
   and BCNF per table; do not merely assert that normalization is satisfied.
4. Seed two theatres, multiple screens, movies, dates, showtimes, and seats,
   together with an illustrative booking and payment event.
5. Document short InnoDB transactions that lock inventory rows in a consistent
   order before holding or confirming seats. Acquire all requested seats or none.
6. Persist hold ownership and expiry. Check expiry in transactions and document
   scheduled cleanup. An expired hold must never confirm seats reassigned to
   another customer; late successful payments require a refund/reconciliation
   path rather than reclaiming those seats.
7. Use unique provider/event identifiers and transactional processing to prevent
   duplicate webhook effects. Describe idempotent booking confirmation as well.

## P2: Showtime query

- Set theatre ID and selected date with MySQL variables.
- Join shows, movies, screens, and theatres.
- Filter by theatre ID and a half-open date interval, keeping functions off the
  indexed show-start column.
- Return one row per show: movie title, screen name, show date, and show time.
- Order by movie title, show start time, and show ID for deterministic results.
- Explain that the date picker offers today and the following six dates.

## Verification

1. Execute P1 on a clean MySQL database, then execute P2.
2. Compare returned rows with the documented sample output.
3. Test the same date at different theatres, multiple showtimes for one movie,
   and a date with no shows.
4. Check invalid foreign keys, invalid seat/screen combinations, and duplicate
   inventory allocations.
5. Use two database sessions to demonstrate that competing claims for the same
   show seat cannot both succeed.
6. Verify hold expiry, stale confirmation rejection, and duplicate payment
   handling with the documented transaction examples.
7. Record actual verification results; do not claim tests that were not run.

## Defaults and GitHub submission

- MySQL 8.0.16 or newer, using InnoDB.
- Execute against local MySQL Community Server using the MySQL command-line
  client; Workbench is optional. Do not use a signed-in online database platform.
  No cloud subscription or trial credits are needed, and Docker is not required.
  Install/configure the local server and verify InnoDB before SQL batches.
- Indian local time used consistently for this assignment.
- Markdown is the submission document, readable directly on GitHub.
- The screenshot is not available in this workspace; implement the described
  date-picker/showtime behavior without inventing extra UI requirements.
- Update README.md after every implementation step with the changes, usage,
  and actual verification results. Review and finalize it after completion.
- Validate the schema, migration, and transaction API together using
  sql/tests/verify_bcnf.py, and record actual execution results.
- Push the initial setup to main in `baigny/movie-seat-booking-theatre`.
  Implement SQL on `feature/p1-p2-sql` and open a PR into main.

## References

- [Ghanshyam's Airtribe database assignment](https://github.com/ghanshyamca/BookMyShow-database-design):
  README, schema.sql, and queries.sql; documents MySQL CLI execution and uses
  InnoDB. Reference for submission organization, not proof of concurrency safety.

- [Airtribe-tagged bms-api](https://github.com/chinmaykunkikar/bms-api): community
  reference for a theatre/date/showtime API; not verified as an official solution.
- [Similar P1/P2 assignment](https://github.com/adityasinghbaghel/BookMyShow-design):
  useful document structure, but its SQL contains mismatched INSERT columns and
  placeholder ellipses. Write and validate our SQL independently.
