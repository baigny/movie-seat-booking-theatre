# Movie Seat Booking Theatre — Data Modeling

Repository: [baigny/data-modeling-movie-seat-booking-theatre](https://github.com/baigny/data-modeling-movie-seat-booking-theatre)

P1/P2 submission in preparation. See [PLAN.md](PLAN.md) for the agreed scope,
implementation steps, verification, and references.

The final [schema review](SCHEMA_REVIEW.md) completes the data dictionary,
relationships, candidate keys, normalization analysis, and enforcement limits.
The schema intentionally includes a BCNF exception in show_seats. Batch sections
below retain the implementation history; current verification is summarized in
the runtime and clean-database sections.

## Submission files

- [sql/p1.sql](sql/p1.sql): all ten table definitions verified from user-provided
  MySQL output through batch 9. All ten tables now have sample data verified
  through batch 11. Nine constraint checks, row-lock exclusion, and six lifecycle
  checks passed, including a clean-database run; broader concurrency coverage remains.
- [sql/p2.sql](sql/p2.sql): default output, alternate theatre/date inputs, and
  empty-result behavior verified from user-provided MySQL output.

## Target database

MySQL 8.0.16 or newer with InnoDB. Dates and showtimes use Indian local time
consistently for this assignment.

Execution will use local MySQL Community Server and the MySQL command-line
client; Workbench is an optional visual editor. No signed-in online database
platform, cloud subscription, or trial credits are required. The user's MySQL
session output confirms successful login and InnoDB as DEFAULT on server 8.4.9.
MySQL Community Server 8.4.9
and its command-line client are installed locally; the MySQL84 service is running.

## Development workflow

- Update this README after each step, including changes and verification results.
- Add two new SQL statements per implementation commit, together with their
  README documentation. Validate, commit, and push each batch before the next.
- Keep setup/documentation-only commits separate from SQL batches.
- Review and finalize the entire README when the project is complete.
- Push setup files to main, then develop P1/P2 on `feature/p1-p2-sql` and submit
  a pull request into main.

## Verify InnoDB

Run these checks in a connected MySQL Workbench SQL tab or MySQL command-line
session. These are diagnostic queries, not the P1/P2 implementation batches.

```sql
SHOW ENGINES;
```

Find the InnoDB row: SUPPORT should be DEFAULT (enabled and default) or YES
(enabled). Transactions, XA, and Savepoints should show YES.

After selecting the project database and creating its tables, check the actual
table engines:

```sql
SELECT TABLE_NAME, ENGINE
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
```

Every project table should show InnoDB. An empty result does not verify anything:
select the project database and ensure its tables have been created first.
The schema will explicitly specify ENGINE=InnoDB on each CREATE TABLE statement.

References: [engine availability](https://dev.mysql.com/doc/refman/8.4/en/innodb-check-availability.html)
and [table metadata](https://dev.mysql.com/doc/mysql-infoschema-excerpt/8.0/en/information-schema-tables-table.html).

## SQL batch 1: Create and select the database

The first two statements in sql/p1.sql create movie_seat_booking with utf8mb4
and select it for subsequent commands. IF NOT EXISTS avoids recreating an
existing database; it does not modify an existing database's configuration.

From the connected mysql prompt, execute:

```text
SOURCE C:/data-modelling-movie-theatre/sql/p1.sql;
```

Then verify the selected database:

```sql
SELECT DATABASE();
```

Verified result from the user's MySQL session: SOURCE completed without a
reported error, and SELECT DATABASE() returned movie_seat_booking.
The verified batch added two executable statements. Subsequent batches append
new statements to the script.

## SQL batch 2: Theatres and screens

Status: verified from the user's MySQL session output. Adds two CREATE TABLE statements, both
explicitly using InnoDB. One theatre can have many screens.

| Table | Column | Type | Rules / meaning |
| --- | --- | --- | --- |
| theatres | theatre_id | INT UNSIGNED | Auto-increment primary key |
| theatres | theatre_name | VARCHAR(150) | Required name; names can repeat at different locations |
| theatres | address | VARCHAR(500) | Required address, treated as one display value |
| screens | screen_id | INT UNSIGNED | Auto-increment primary key |
| screens | theatre_id | INT UNSIGNED | Required foreign key to theatres |
| screens | screen_name | VARCHAR(50) | Required; unique within its theatre |

The theatre foreign key prevents orphan screens and restricts deleting a theatre
that still has screens. The unique key (theatre_id, screen_name) also supports
looking up a theatre's screens. Counts of screens are computed rather than stored.

Normalization assumptions: a theatre name or address alone does not uniquely
identify a theatre. For theatres, theatre_id determines all attributes. For
screens, both screen_id and (theatre_id, screen_name) are candidate keys and
determine all attributes. Values are atomic, with no partial or transitive
dependencies under these assumptions; both tables satisfy 1NF through BCNF.

For this step, run sql/p1.sql once from the mysql prompt using SOURCE as above.
The database setup can repeat, but CREATE TABLE statements intentionally fail if
the tables already exist; do not repeatedly source the file after success.
For future batches, execute only the newly added statements against this database.

Verify this batch with:

```sql
SHOW TABLES;
SHOW CREATE TABLE screens;
```

Expected tables: theatres and screens. The screens definition should include
ENGINE=InnoDB, its primary key, the composite unique key, and the theatre foreign
key. Sample INSERT statements will be supplied in later batches.

Observed verification: SHOW TABLES returned screens and theatres. SHOW CREATE
TABLE screens confirmed InnoDB, utf8mb4, the primary key, uq_screens_theatre_name,
and fk_screens_theatre with RESTRICT actions. Negative constraint tests are pending.

## SQL batch 3: Theatre and screen sample rows

Status: verified from user-provided MySQL output. Two INSERT statements add fictional
sample data with explicit IDs so later examples have stable references.

| theatre_id | theatre_name | address |
| --- | --- | --- |
| 1 | Starlight Cinema | 10 Sample Road, Bengaluru, Karnataka, India |
| 2 | Moonlight Cinema | 20 Example Road, Chennai, Tamil Nadu, India |

| screen_id | theatre_id | screen_name |
| --- | --- | --- |
| 1 | 1 | Screen 1 |
| 2 | 1 | Screen 2 |
| 3 | 2 | Screen 1 |

Execute only the two INSERT statements under Batch 3 in sql/p1.sql, once, in
the existing movie_seat_booking database. Do not source the entire script again.
Screen 1 appears in both theatres, demonstrating that its name is unique only
within a theatre. Verify with SELECT * FROM theatres ORDER BY theatre_id and
SELECT * FROM screens ORDER BY screen_id; expected counts are two and three.

Observed: INSERT results reported two and three affected rows respectively,
with zero duplicates and warnings. Both SELECT results matched the rows above.

## SQL batch 4: Movies and physical seats

Status: verified from user-provided SHOW CREATE TABLE output for both tables.
Seats has the expected columns, primary key, uq_seats_position, fk_seats_screen
with RESTRICT actions, and chk_seats_number. Movies has its expected columns,
primary key, and chk_movies_duration. Both use InnoDB and utf8mb4.

| Table | Column | Type | Rules / meaning |
| --- | --- | --- | --- |
| movies | movie_id | INT UNSIGNED | Auto-increment primary key |
| movies | title | VARCHAR(200) | Required title; different movies may share a title |
| movies | duration_minutes | SMALLINT UNSIGNED | Required positive running time |
| seats | seat_id | INT UNSIGNED | Auto-increment primary key |
| seats | screen_id | INT UNSIGNED | Required foreign key to screens |
| seats | row_label | VARCHAR(5) | Required row label, for example A |
| seats | seat_number | SMALLINT UNSIGNED | Required positive seat number |

The composite unique key (screen_id, row_label, seat_number) prevents duplicate
physical positions within a screen. Seats describe the permanent layout; their
availability will be recorded per show, not on these physical seat rows.

Normalization: movie_id determines title and duration; titles are not assumed
unique. Both seat_id and (screen_id, row_label, seat_number) are candidate keys
for seats. All values are atomic and all nontrivial functional dependencies have
candidate-key determinants under these assumptions, satisfying BCNF and 1NF-3NF.

Run only the two new CREATE TABLE statements under Batch 4 in sql/p1.sql.
Do not source the whole script into the existing populated database.
Verify using SHOW CREATE TABLE movies and SHOW CREATE TABLE seats. Expect
InnoDB on both tables, positive-value CHECK constraints, and the seat-position
unique key plus screen foreign key. Runtime rejection tests will follow later.

## SQL batch 5: Movie and seat sample rows

Status: verified from user-provided MySQL output. Adds two INSERT statements with fictional
movie details and a deliberately small seating layout for reproducible examples.

| movie_id | title | duration_minutes |
| --- | --- | --- |
| 1 | Journey to the Stars | 120 |
| 2 | The Last Train | 105 |
| 3 | Ocean of Dreams | 135 |

| seat_id | screen_id | row_label | seat_number |
| --- | --- | --- | --- |
| 1 | 1 | A | 1 |
| 2 | 1 | A | 2 |
| 3 | 1 | B | 1 |
| 4 | 1 | B | 2 |
| 5 | 2 | A | 1 |
| 6 | 2 | A | 2 |
| 7 | 3 | A | 1 |
| 8 | 3 | A | 2 |

Execute only the two INSERT statements under Batch 5 in sql/p1.sql, once, in
movie_seat_booking. Verify with SELECT * FROM movies ORDER BY movie_id and
SELECT * FROM seats ORDER BY seat_id; expect three movies and eight seats.
Seats such as A1 may repeat on different screens, and seat number 1 may repeat
on different rows within a screen. The full screen/row/number position is unique.

Observed: both INSERT statements succeeded with three and eight affected rows,
zero duplicates, and zero warnings. SELECT results matched every sample row.
Rerunning the earlier batch 4 CREATE TABLE statements produced error 1050 because
the tables already existed; those errors did not affect the successful inserts.

## SQL batch 6: Shows and customers

Status: verified from user-provided MySQL output. Both CREATE TABLE statements
succeeded. SHOW CREATE TABLE confirmed InnoDB, all expected columns, the
screen/start and email unique keys, both show foreign keys with RESTRICT actions,
and the nonnegative ticket-price CHECK constraint.

| Table | Column | Type | Rules / meaning |
| --- | --- | --- | --- |
| shows | show_id | INT UNSIGNED | Auto-increment primary key |
| shows | movie_id | INT UNSIGNED | Required foreign key to movies |
| shows | screen_id | INT UNSIGNED | Required foreign key to screens |
| shows | starts_at | DATETIME | Required start in Indian local time |
| shows | ticket_price | DECIMAL(10,2) | Required nonnegative price in INR |
| users | user_id | INT UNSIGNED | Auto-increment primary key |
| users | full_name | VARCHAR(150) | Required customer name |
| users | email | VARCHAR(254) | Required unique email |

Each show references one movie and one screen. All seats in a show have the same
listed ticket price for this assignment. Historical purchase prices will be
stored separately on booking items. Theatre details are obtained through screens.
The unique (screen_id, starts_at) key prevents identical starts on the same screen
and supports P2's screen/date-range lookup. It does not prevent overlapping movie
intervals; scheduling must check overlaps while locking the screen row.

Normalization: show_id and (screen_id, starts_at) are candidate keys for shows;
user_id and email are candidate keys for users. Email equality uses the database
collation. All other attributes depend on a candidate key, with atomic values
and no partial or transitive dependencies under the stated assumptions (BCNF,
and therefore 1NF-3NF). Movie duration and theatre name are not copied into shows.
User authentication is outside this SQL assignment, so no passwords are stored.

Run only the two CREATE TABLE statements under Batch 6 in sql/p1.sql. Verify
using SHOW CREATE TABLE shows and SHOW CREATE TABLE users. Expect InnoDB on
both, the movie/screen foreign keys, the screen/start unique key, the price CHECK,
and the unique user email. Runtime constraint tests are still pending.

## SQL batch 7: Sample shows and customers

Status: batch acceptance verified from user-provided output. SELECT output
matches both customer rows; COUNT(*) confirms two users and ten shows. Individual
show values have not yet been checked against database output; P2 testing will
verify the show details and theatre/date filtering.
Two INSERT statements add ten shows and two fictional customers.
Dates are fixed for repeatable P2 results: use selected
date 2026-09-28 instead of relying on today's date when testing this fixture.
Times are Indian local time and prices are INR.

| show_id | movie_id | screen_id | starts_at | ticket_price |
| --- | --- | --- | --- | --- |
| 1 | 1 | 1 | 2026-09-28 10:00:00 | 200.00 |
| 2 | 1 | 1 | 2026-09-28 14:00:00 | 220.00 |
| 3 | 2 | 2 | 2026-09-28 11:00:00 | 180.00 |
| 4 | 3 | 3 | 2026-09-28 10:00:00 | 250.00 |
| 5 | 2 | 1 | 2026-09-29 10:00:00 | 200.00 |
| 6 | 3 | 1 | 2026-09-30 10:00:00 | 240.00 |
| 7 | 1 | 1 | 2026-10-01 10:00:00 | 200.00 |
| 8 | 2 | 1 | 2026-10-02 10:00:00 | 200.00 |
| 9 | 3 | 1 | 2026-10-03 10:00:00 | 260.00 |
| 10 | 1 | 1 | 2026-10-04 10:00:00 | 220.00 |

| user_id | full_name | email |
| --- | --- | --- |
| 1 | Asha Rao | asha@example.com |
| 2 | Ravi Kumar | ravi@example.com |

The first theatre has multiple movies and showtimes on the first date, plus
shows on each of the following six dates. The second theatre has its own show
at the same time as a first-theatre show, testing theatre isolation in P2.

Run only the two INSERT statements under Batch 7. Verify with SELECT * FROM
shows ORDER BY show_id and SELECT * FROM users ORDER BY user_id; expect ten
shows and two users. Do not rerun the entire script against the populated database.

## SQL batch 8: Bookings and show-seat inventory

Status: table creation and definitions verified from user-provided MySQL output.
Both CREATE TABLE statements succeeded. SHOW TABLES returned eight tables;
SHOW CREATE TABLE confirmed the expected columns, defaults, primary and unique
keys, indexes, foreign keys with RESTRICT actions, and CHECK constraints. Both
tables use InnoDB and utf8mb4. COUNT(*) returned zero for each new table, as
expected before seeding. Runtime constraint rejection and concurrency tests
remain pending.

Adds two InnoDB tables. `bookings` records the customer, scheduled show,
reference, lifecycle status, hold deadline, and amount. The show is referenced
by its candidate key `(screen_id, starts_at)`. A held booking must have a
deadline; transaction examples below use the database clock and retain the
deadline when a booking changes status.

`show_seats` stores one row per show and physical seat. Its composite primary
key prevents duplicate inventory; foreign keys require both a real show and a
seat on that show's screen. `booking_id` is nullable for available inventory;
held or sold inventory must reference a booking for the same show. The status
index supports finding and locking requested seats in a deterministic order.

Candidate keys: `booking_id` and `booking_reference` identify a booking;
`(booking_id, screen_id, starts_at)` is a redundant unique superkey for enforcing
show-consistent allocations. The show-seat primary key identifies an inventory
row. In bookings, each non-key attribute depends on a candidate key, with no
partial or transitive dependencies; bookings satisfies BCNF under these
assumptions. In show_seats, availability and booking allocation depend on the
full show/seat key. For allocated rows, booking_id also determines screen_id
and starts_at through bookings, although booking_id is not an inventory key.
This intentionally repeats the booking's show coordinates to enforce same-show
allocation with a composite foreign key. Accordingly, show_seats should not be
claimed to satisfy BCNF without qualification; it trades strict normalization
for declarative allocation integrity. NULL ownership represents free inventory.

Run only the two CREATE TABLE statements under Batch 8 after batch 7. Verify
using `SHOW CREATE TABLE bookings`, `SHOW CREATE TABLE show_seats`, and the
table counts. The next batches add sample inventory, booking items, and payment
events.

## SQL batch 9: Booking items and payment events

Status: table definitions and empty row counts verified from user-provided MySQL
output. SHOW TABLES returned all ten tables. SHOW CREATE TABLE confirmed both
new tables' columns, defaults, primary keys, foreign keys with RESTRICT actions,
and CHECK constraints, plus the payment provider/event unique key and booking
index. Both tables use InnoDB and utf8mb4; payment identifiers use ascii_bin as
specified. COUNT(*) returned zero for each table. Runtime constraint rejection,
payment idempotency, and concurrency tests remain pending.
Adds exactly two CREATE TABLE statements to sql/p1.sql.

| Table | Column | Type | Rules / meaning |
| --- | --- | --- | --- |
| booking_seats | booking_id | INT UNSIGNED | Required foreign key to bookings; part of primary key |
| booking_seats | row_label | VARCHAR(5) | Seat row within the booking's screen; part of primary key |
| booking_seats | seat_number | SMALLINT UNSIGNED | Positive seat number; part of primary key |
| booking_seats | purchase_price | DECIMAL(10,2) | Nonnegative historical item price in INR |
| payment_events | payment_event_id | BIGINT UNSIGNED | Auto-increment primary key |
| payment_events | provider | VARCHAR(50) | Required ASCII provider identifier |
| payment_events | provider_event_id | VARCHAR(191) | Required ASCII event identifier; unique together with provider |
| payment_events | booking_id | INT UNSIGNED | Required foreign key to bookings |
| payment_events | event_type | ENUM | payment_succeeded, payment_failed, or refund_succeeded |
| payment_events | amount | DECIMAL(10,2) | Nonnegative event amount in INR |
| payment_events | processing_status | ENUM | pending (default), applied, ignored, or refund_required |
| payment_events | received_at | DATETIME | Database timestamp on receipt |
| payment_events | processed_at | DATETIME | NULL while pending; required after processing |

One booking has many historical seat items and may have many payment events.
Both tables use InnoDB and restrict deletion or key changes of referenced
bookings. The booking item primary key prevents repeating a seat in one booking.
The same seat can appear in a later booking after cancellation or expiry;
show_seats remains the authority for current ownership.

The booking determines its screen and show, so booking_seats does not duplicate
screen_id or starts_at. Its booking foreign key alone does not validate a seat
position. The booking transaction must join the booking to matching show_seats,
lock those inventory rows, validate ownership, and insert items from those rows
in the same transaction. It must also reconcile total_amount with item prices.
These transaction examples and their runtime tests are still pending.

Payment provider and event identifiers use case-sensitive ASCII comparison;
the assignment assumes provider IDs fit these lengths and contain ASCII only.
The unique pair prevents storing the same provider event twice. It does not
alone make payment handling idempotent: event processing must lock the booking,
validate amount, expiry, and current inventory ownership, then update booking,
inventory, and event outcome atomically. Distinct success events must not confirm
an already confirmed booking again. Late successful payments are recorded as
refund_required without reclaiming reassigned seats. External refunds and their
retries require an idempotent provider operation; this table records outcomes.

Normalization: (booking_id, row_label, seat_number) is the booking item candidate
key; purchase_price depends on the complete key and is a historical snapshot,
not a copy that follows the current show price. payment_event_id and
(provider, provider_event_id) are payment event candidate keys; each determines
the event's booking, type, amount, processing state, and timestamps. No other
functional dependencies are assumed. Both tables have atomic values, no partial
or transitive dependencies on candidate keys, and only candidate-key determinants
for nontrivial dependencies (1NF, 2NF, 3NF, and BCNF).

Run only the two CREATE TABLE statements under Batch 9 in the existing database.
Do not source all of p1.sql again. Verify with SHOW TABLES, SHOW CREATE TABLE for
both new tables, and COUNT(*) for each. Expect ten tables and zero rows in each
new table. Sample rows and negative constraint tests follow in later batches.

## SQL batch 10: Sample booking and show-seat inventory

Status: verified from user-provided MySQL output. The booking INSERT affected
one row; the inventory INSERT affected 36 rows with zero duplicates and warnings.
The booking SELECT matched every expected field. Inventory checks returned
36 rows: two sold seats (A1 and A2 for booking 1 on screen 1 at
2026-09-28 10:00:00) and 34 available seats with NULL booking_id. Grouped
counts matched all ten shows: four seats for each of screen 1's eight shows,
and two seats each for the shows on screens 2 and 3. Runtime constraint and
concurrency tests remain pending.
Adds two INSERT statements, to be run once after batch 9.

The first creates booking 1 for Asha Rao (user 1), screen 1 at
2026-09-28 10:00:00, with reference 00000000-0000-4000-8000-000000000001.
It is a fixed historical confirmed booking for seats A1 and A2, totaling INR
400.00 (two seats at INR 200.00). created_at is 2026-09-27 18:00:00 and the
retained hold deadline is 2026-09-27 18:10:00. The deadline does not expire an
already confirmed booking. This fixture does not demonstrate live confirmation;
batch 11 will add its historical booking items and successful payment event.
Until that batch, the sample booking's audit data is incomplete.

The second INSERT joins shows to physical seats on screen_id, generating one
inventory row for each seat on each show's screen. A left join to booking 1
marks only its matching show and seats A1/A2 as sold, owned by booking 1. All
other inventory is available with NULL booking_id. This seeds the assignment
fixture; live allocation must use the locking transactions still to be added.

Expected results with the unchanged earlier fixtures:

| Check | Expected |
| --- | --- |
| bookings rows | 1 |
| show_seats rows | 36 |
| sold inventory | 2, both for booking 1 on screen 1 at 2026-09-28 10:00:00 |
| available inventory | 34, all with NULL booking_id |
| inventory per show | 4 for each of screen 1's eight shows; 2 each for screens 2 and 3 |

Run only Batch 10's two INSERT statements in movie_seat_booking; do not source
the full p1.sql or rerun successful inserts. Verify the booking row, total and
status counts, sold seat details, and inventory counts grouped by show.

## SQL batch 11: Sample booking items and successful payment

Status: verified from user-provided MySQL output. The booking item INSERT
affected two rows with zero duplicates and warnings; the payment event INSERT
affected one row. SELECT results matched every inserted field, including both
INR 200.00 seat prices, the INR 400.00 applied payment, and its timestamps.
The item sum and booking total both returned INR 400.00. The inventory join
confirmed A1 and A2 are sold to booking 1. Runtime constraint rejection,
payment idempotency, and concurrency tests remain pending.
Adds exactly two INSERT statements, to be run once after batch 10.

The first adds booking 1's historical items: A1 and A2 at INR 200.00 each.
Their INR 400.00 total matches bookings.total_amount, and both positions match
the inventory sold to that booking on screen 1 at 2026-09-28 10:00:00.

The second adds a fictional payment event with payment_event_id 1, provider
demo_provider, provider_event_id evt_demo_001, and booking_id 1. Its event_type
is payment_succeeded, amount is INR 400.00, and processing_status is applied.
received_at is 2026-09-27 18:05:00 and processed_at is 2026-09-27 18:05:01,
both before the retained hold deadline. These fixed timestamps describe the
historical fixture independently of the date on which the script is executed.
No external payment is made. Inserting an applied event is sample data, not
proof of idempotent processing or safe concurrent confirmation; those tests
and transaction examples remain pending.

All ten tables now have verified sample data. Expect two
booking_seats rows and one payment_events row. Verify every inserted field,
compare the item sum and payment amount to the booking total, and join items
through the booking's screen/start to show_seats to confirm both are sold to
booking 1. Do not rerun successful inserts or source the complete p1.sql into
the populated database.

## P1 runtime verification

Status: all nine constraint rejection tests passed, verified from user-provided
MySQL output showing PASS: constraint rejection tests and tests_passed = 9.
The procedure call and cleanup completed without reported unhandled errors.
Two-session row-lock exclusion also passed from user-provided output: session A
selected B1 with FOR UPDATE, session B's competing UPDATE received error 1205,
and B's final SELECT returned available / NULL after rollback. The later lifecycle
test acquired B1 successfully, showing the earlier lock no longer blocked it.
All six single-session lifecycle protocol checks also passed from user-provided
output; B1 returned to available / NULL after rollback. Diagnostic test
statements are separate from the two-statement implementation batches.

From the logged-in mysql prompt, run:

```text
SOURCE C:/data-modelling-movie-theatre/sql/tests/p1_constraints.sql;
```

Expect a PASS result with tests_passed = 9 and no unhandled errors. The script
checks an orphan foreign key, duplicate inventory, wrong-screen seat,
wrong-show booking allocation, sold inventory without an owner, a held booking
without expiry, negative item price, duplicate payment event, and an applied
event without its processing timestamp. Expected error numbers are handled
inside a test procedure; an unexpected error aborts the procedure and rolls
back. The procedure is removed afterward. Test writes are rolled back, although
auto-increment counters may advance. Requires CREATE ROUTINE and EXECUTE access.

For the two-session lock exclusion test, open two independent mysql clients.
Run sql/tests/p1_lock_session_a.sql in A, keeping that connection open. Confirm
it selected available B1 with NULL booking_id. Then run
sql/tests/p1_lock_session_b.sql in B. Its UPDATE must receive error 1205 after
about three seconds; the final SELECT must show available / NULL. Run ROLLBACK
in A afterward. B rolls back and restores its previous lock timeout itself.
This proves exclusion while A holds a row lock; it does not yet prove the full
booking, hold-expiry, stale-confirmation, or payment-idempotency protocol.
The single-session lifecycle checks below complement this lock exclusion test;
broader concurrent lifecycle races and multi-seat atomicity remain unverified.

### Hold expiry, stale confirmation, and payment replay tests

Status: verified from user-provided MySQL output. sql/tests/p1_lifecycle.sql
returned PASS: lifecycle protocol tests with tests_passed = 6 and no reported
unhandled errors. The final B1 row was available with NULL booking_id.
First run ROLLBACK in session A from the locking test, then source this file
in one logged-in MySQL session. Expect PASS: lifecycle protocol tests with
tests_passed = 6, followed by B1 available / NULL after rollback.

The procedure creates two temporary booking records within its transaction and
locks B1. It tests expired-hold cleanup, reassignment to a new owner, rejection
of stale confirmation with a refund_required event, valid owner confirmation,
duplicate provider-event rejection, and repeated confirmation as a no-op.
All data changes roll back on success or an unhandled error; generated IDs may
leave gaps. The procedure itself is removed after the call. It uses the past
fixture show intentionally to isolate hold lifecycle behavior; live sales must
also reject shows that have already started.

These are executable protocol examples, not tests of an application service:
this project has no booking service or webhook handler. The refund outcome is
recorded directly; no external refund is executed. This single-session script
does not establish safety for every concurrent lifecycle race. Existing booking
rows must be locked before inventory rows, with multiple booking IDs and seat
keys locked in consistent order across confirmation and cleanup. Multi-seat
operations must check that every requested seat was updated and roll back the
whole transaction on a count mismatch. Duplicate event handling must skip
effects after checking the original event's booking and amount; a distinct
payment for an already confirmed booking requires reconciliation rather than
another seat allocation. Scheduled cleanup must recheck expiry and ownership
under those same locks. Further multi-seat and concurrent lifecycle coverage
remains pending; do not infer production readiness from these six checks.

## SQL batch 12: P2 theatre/date showtimes

Status: default input verified from user-provided MySQL output. Theatre 1 on
2026-09-28 returned exactly the three expected rows below, including both
Journey to the Stars showtimes, with matching screen names, dates, and order.
The additional sql/tests/p2_filters.sql run returned one Ocean of Dreams row
for theatre 2 on 2026-09-28, one The Last Train row for theatre 1 on 2026-09-29,
and an empty set for theatre 1 on 2026-10-05. The first pasted result contained
overlapping terminal formatting, but its expected row and one-row count were
visible. All four fixture cases now have user-provided execution evidence.
sql/p2.sql contains two statements: one SET for both input variables and one
SELECT joining shows, movies, screens, and theatres. Fully qualified tables
allow execution regardless of the connection's currently selected database.

Run from the logged-in mysql prompt:

```text
SOURCE C:/data-modelling-movie-theatre/sql/p2.sql;
```

The default inputs are theatre 1 and the fixed fixture date 2026-09-28. Expected:

| movie_title | screen_name | show_date | show_time |
| --- | --- | --- | --- |
| Journey to the Stars | Screen 1 | 2026-09-28 | 10:00:00 |
| Journey to the Stars | Screen 1 | 2026-09-28 | 14:00:00 |
| The Last Train | Screen 2 | 2026-09-28 | 11:00:00 |

The query returns one row per show, ordered by movie title, start time, and
show ID. Its half-open interval includes midnight on the selected date and
excludes midnight on the next date. No function wraps starts_at in the WHERE
clause, allowing the existing screen/start index to support date-range lookup.
DATE and TIME format only the output columns.

For additional checks, change the SET inputs in the file before sourcing it,
or set the variables in the client and rerun only the SELECT. Sourcing the
unchanged file resets both inputs to the defaults.

| Theatre | Date | Expected result |
| --- | --- | --- |
| 2 | 2026-09-28 | Ocean of Dreams, Screen 1, 10:00:00 only |
| 1 | 2026-09-29 | The Last Train, Screen 1, 10:00:00 only |
| 1 | 2026-10-05 | No rows |

The intended date picker offers today and the following six dates using Indian
local time. This repository has no frontend; the SQL accepts the selected date
and also allows fixed historical dates for fixture verification. The fixture
does not move forward automatically as today's date changes.

## Reference execution workflow

[Ghanshyam's Airtribe database assignment](https://github.com/ghanshyamca/BookMyShow-database-design)
documents importing schema.sql and queries.sql through the MySQL command-line
client. Its schema explicitly uses InnoDB. We will use the same file-based
workflow with our own independently validated SQL and record actual results.

## Clean-database verification

Status: verified from user-provided MySQL output on 2026-09-29 in the fresh
schema movie_verify_905763b6db41489e8439e391d1ec02c4. No errors were reported.
P1 creation and inserts completed, all four P2 cases matched, constraint tests
passed 9/9, and lifecycle tests passed 6/6. B1 returned to available / NULL.
All ten final row counts matched the table below and every table used InnoDB.
The script completed its final switch back to the project database.

To prepare another independent run, from PowerShell in the repository run
`./sql/tests/prepare_clean_run.ps1`. It generates an ignored SQL file with a
fresh GUID-based schema name, replacing only the project schema references.
The copy executes P1, P2, the alternate P2 filters, nine constraint checks, and
six lifecycle checks. It then reports table counts and engines and switches
back to movie_seat_booking. The original database and source SQL are preserved.
The generated copy uses CREATE DATABASE without IF NOT EXISTS; run it once.
If any error occurs, retain the output and stop verification; do not interpret
later output as proof that earlier statements succeeded. Generate a new file
for a fresh attempt. The verification schema is retained for inspection.

At the mysql prompt, execute the SOURCE command printed by the generator.
Expect the four previously verified P2 result sets, PASS counts 9 and 6, all
ten engines InnoDB, and these final row counts:

| Table | Rows |
| --- | --- |
| theatres | 2 |
| screens | 3 |
| movies | 3 |
| seats | 8 |
| shows | 10 |
| users | 2 |
| bookings | 1 |
| show_seats | 36 |
| booking_seats | 2 |
| payment_events | 1 |

This single-session run does not repeat the two-client locking test.

## Broader concurrency checks

The [committed-winner test](sql/tests/RACE_TESTS.md) is prepared in a separate
generated schema. It checks that a losing two-seat request rolls back its partial
claim after waiting for a winner to commit, and that replay cannot replace the
winner's payment event. Follow its two-terminal sequence and report both PASS
rows plus whether terminal B waited. Execution remains pending. This extends
the timeout-only test; it does not simulate concurrent external webhook workers
or expiry-versus-confirmation races.
