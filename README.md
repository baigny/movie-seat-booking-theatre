# Movie Seat Booking Theatre — Data Modeling

Repository: [baigny/data-modeling-movie-seat-booking-theatre](https://github.com/baigny/data-modeling-movie-seat-booking-theatre)

P1/P2 submission in preparation. See [PLAN.md](PLAN.md) for the agreed scope,
implementation steps, verification, and references.

Track current status and completed commits in [PROGRESS.md](PROGRESS.md).

## Submission files

- [sql/p1.sql](sql/p1.sql): database setup added; tables and sample data pending.
- [sql/p2.sql](sql/p2.sql): shows by theatre and date (pending).

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
- Update PROGRESS.md alongside this README so completed and pending batches stay visible.
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

## Progress

- Plan created; SQL batch 1 (database setup) verified from user-provided output.
- Step 1: GitHub repository created and confirmed empty before initial upload.
- Step 2: Initial setup contains the README, project plan, and SQL placeholders.
  SQL implementation will begin on `feature/p1-p2-sql` after this baseline commit.
- Incremental README updates and two-statement SQL batches agreed.
- Initial environment checks did not find mysql on PATH; use the installed
  client's full path if the shell still cannot resolve mysql.
- Step 3 (environment check): no MySQL command, matching Windows service, or
  installation in the standard MySQL Program Files locations was found.
  Docker CLI is installed, but its Linux engine is not running.
- Step 4 (execution approach): use local MySQL rather than a signed-in online
  database platform. Next, set up MySQL Community Server and its client, then
  verify the server version and InnoDB. Docker is not required.

## Local installation progress

- Step 5: Installed Oracle.MySQL 8.4.9 through Windows Package Manager from
  MySQL's official download. The installer hash was verified successfully.
- Verified the installed client with mysql.exe --version: MySQL Community
  Server 8.4.9 for Win64.
- No MySQL Windows service was present immediately after installation. A later
  check confirmed MySQL84 is Running and the server responds on localhost.
- An unauthenticated mysqladmin probe received Access denied; this confirms
  a server response, not successful login or InnoDB verification.
- Step 6: The user connected successfully and supplied SELECT VERSION() and
  SHOW ENGINES output. Server version: 8.4.9; InnoDB: DEFAULT; Transactions,
  XA, and Savepoints: YES. These results are user-provided execution evidence.
- Passwords belong in your local credential storage, not in these project files.

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

## Reference execution workflow

[Ghanshyam's Airtribe database assignment](https://github.com/ghanshyamca/BookMyShow-database-design)
documents importing schema.sql and queries.sql through the MySQL command-line
client. Its schema explicitly uses InnoDB. We will use the same file-based
workflow with our own independently validated SQL and record actual results.

## Remaining documentation

The completed submission will include a table-by-table data dictionary,
relationships, example rows, normalization reasoning through BCNF, concurrency
transaction examples, execution instructions, and actual verification results.
