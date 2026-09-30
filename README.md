# Movie Theatre Booking - P1 & P2

> Movie seat booking database assignment using MySQL/InnoDB, normalized through BCNF and verified under concurrent seat-booking workloads.

**Repository:** https://github.com/baigny/movie-seat-booking-theatre
**Pull Request:** https://github.com/baigny/movie-seat-booking-theatre/pull/1
**Implementation branch:** `feature/p1-p2-sql`

The project contains an executable MySQL schema, sample data, theatre/date showtime query, transactional seat locking, timed hold expiry, idempotent payment-event handling, restricted application privileges, and a reproducible concurrency/integration test suite.

> **Scope note:** Redis, queues, an HTTP backend, external payment-provider integration/signature verification, and frontend UI are outside this repository's scope. Timed release is implemented with an optional MySQL Event Scheduler workflow.

---

## Index

1. [Project Requirements Covered](#1-project-requirements-covered)
2. [Repository Structure](#2-repository-structure)
3. [Prerequisites](#3-prerequisites)
4. [Execution Order](#4-execution-order)
5. [Command Index](#5-command-index)
6. [P1 - Database Design](#6-p1---database-design)
7. [Normalization](#7-normalization)
8. [P2 - Theatre/Date Showtime Query](#8-p2---theatredate-showtime-query)
9. [Booking and Concurrency Design](#9-booking-and-concurrency-design)
10. [Automatic Hold Expiry](#10-automatic-hold-expiry)
11. [Application Permission Boundary](#11-application-permission-boundary)
12. [Test Case Index](#12-test-case-index)
13. [Verified Results and Benchmarks](#13-verified-results-and-benchmarks)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Project Requirements Covered

| Requirement | Implementation / Evidence |
|---|---|
| P1 entities, attributes, tables and sample rows | `sql/p1.sql` + `SCHEMA_DESIGN.md` |
| 1NF, 2NF, 3NF and BCNF | Candidate-key and functional-dependency analysis in `SCHEMA_DESIGN.md` |
| Directly executable MySQL SQL | MySQL 8.0.16+ / InnoDB scripts under `sql/` |
| No double-booking / no lost holds | Pessimistic row locking + atomic transaction routines |
| Timed hold release | `expire_booking` + optional MySQL event in `sql/expiry_event.sql` |
| Idempotent payment processing | Unique provider/event key + transactional replay validation |
| P2 theatre/date showtimes | `sql/p2.sql` |
| Concurrency and load verification | `sql/tests/verify_bcnf.py` + `sql/tests/bcnf-results.json` |
| GitHub PR | PR #1 |

---

## 2. Repository Structure

```text
movie-seat-booking-theatre/
|
|-- README.md
|-- SCHEMA_DESIGN.md
|-- PLAN.md
|
`-- sql/
    |-- p1.sql
    |-- p2.sql
    |-- booking_api.sql
    |-- application_role.sql
    |-- expiry_event.sql
    `-- tests/
        |-- verify_bcnf.py
        `-- bcnf-results.json
```

### Main files

| File | Purpose |
|---|---|
| `sql/p1.sql` | 11 BCNF base tables, keys, constraints, indexes and fixture data |
| `SCHEMA_DESIGN.md` | Attributes, relationships, candidate keys, normal-form reasoning and locking trade-offs |
| `sql/booking_api.sql` | `seat_availability` view and transactional booking routines |
| `sql/p2.sql` | Shows for a selected theatre and date |
| `sql/application_role.sql` | Restricted client role with `SELECT` + public routine execution only |
| `sql/expiry_event.sql` | Optional scheduled cleanup of expired holds |
| `sql/tests/verify_bcnf.py` | 20 standard checks; 21 including scheduler execution |
| `sql/tests/bcnf-results.json` | Recorded successful execution report |

---

## 3. Prerequisites

- **MySQL:** 8.0.16 or newer with InnoDB
- **Verified version:** MySQL Community Server **8.4.9**
- **Python:** 3.12 for the verification suite
- **Python packages:** none; the test runner uses only the Python standard library
- **MySQL CLI:** required for the automated test runner
- **Time zone used by this assignment:** India Standard Time (`+05:30`)
- **Currency:** INR

Check MySQL:

```sql
SELECT VERSION();
SHOW ENGINES;
```

`InnoDB` should be enabled. After P1 is installed, verify all project tables use InnoDB:

```sql
SELECT TABLE_NAME, ENGINE
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'movie_seat_booking'
  AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
```

---

## 4. Execution Order

Use a fresh database. Follow CMD-01 through CMD-06 for installation and P2.
Run terminal commands from the repository root and start the MySQL client there
so relative SOURCE paths resolve correctly. SQL blocks run at the MySQL prompt;
PowerShell blocks run in the terminal. CMD-02 connects to an already running
MySQL server; it does not start the server.

P1, the booking API and expiry objects are one-time installation scripts.
Do not source them again into populated tables. CMD-08 to CMD-10 demonstrate
the lifecycle on a future show. CMD-12 configures application access;
CMD-13 and CMD-14 install and activate optional automatic expiry.

---

## 5. Command Index

### CMD-01 - Clone and checkout the completed branch

```bash
git clone https://github.com/baigny/movie-seat-booking-theatre.git
cd movie-seat-booking-theatre
git checkout feature/p1-p2-sql
```

### CMD-02 - Open MySQL CLI

```powershell
& "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe" -u root -p
```

### CMD-03 - Set assignment time zone

```sql
SET time_zone = '+05:30';
```

### CMD-04 - Install P1 schema and sample data

```sql
SOURCE sql/p1.sql;
```

### CMD-05 - Install booking transaction API

```sql
SOURCE sql/booking_api.sql;
```

### CMD-06 - Execute the P2 query

```sql
SOURCE sql/p2.sql;
```

### CMD-07 - Run P2 for a different theatre/date

After sourcing `p2.sql`, change the input values and run its `SELECT` statement again:

```sql
SET @theatre_id = 2;
SET @selected_date = DATE('2026-09-28');
```

### CMD-08 - Create a future demo show and hold seats

Run setup as an administrator on a demo database. The new show starts beyond
the current clock and existing screen-1 shows. Use the same MySQL session for
CMD-08 through CMD-10.

```sql
USE movie_seat_booking;
SET time_zone = '+05:30';
SELECT DATE_ADD(GREATEST(SYSDATE(), MAX(starts_at)), INTERVAL 1 DAY)
INTO @demo_start FROM shows WHERE screen_id = 1;
INSERT INTO shows (movie_id, screen_id, starts_at, ticket_price)
VALUES (1, 1, @demo_start, 200.00);
SET @demo_show = LAST_INSERT_ID();
INSERT INTO show_seats (screen_id, starts_at, row_label, seat_number)
SELECT screen_id, @demo_start, row_label, seat_number
FROM seats WHERE screen_id = 1;

SET @demo_reference = UUID();
CALL hold_seats(1, @demo_show, @demo_reference,
    '[{"row":"B","number":1},{"row":"B","number":2}]', 300);
SELECT booking_id INTO @demo_booking
FROM bookings WHERE booking_reference = @demo_reference;
SELECT @demo_booking AS booking_id;
```

The routine returns the booking ID. The unique reference lookup ties later
commands to that booking without assuming an ID. Holds accept 1-20 distinct
seats and a TTL of 1-900 seconds. Any failed seat claim rolls back the whole hold.
The administrative fixture inserts above are separate from that transaction.

### CMD-09 - Confirm a successful payment idempotently

Run within the five-minute hold. Both calls should return applied, with only
one stored provider/event pair.

```sql
SET @demo_event = UUID();
CALL confirm_payment(@demo_booking, 'demo_provider', @demo_event, 400.00);
CALL confirm_payment(@demo_booking, 'demo_provider', @demo_event, 400.00);
```

### CMD-10 - Verify expiry and preserve confirmed seats

Create a separate one-second A1 hold. The expiry calls below should return
expired and confirmed, respectively.

```sql
SET @expiry_reference = UUID();
CALL hold_seats(1, @demo_show, @expiry_reference,
    '[{"row":"A","number":1}]', 1);
SELECT booking_id INTO @expiry_booking
FROM bookings WHERE booking_reference = @expiry_reference;
DO SLEEP(2);
CALL expire_booking(@expiry_booking);
CALL expire_booking(@demo_booking);
```

### CMD-11 - Inspect derived seat availability

```sql
SELECT *
FROM movie_seat_booking.seat_availability
ORDER BY screen_id, starts_at, row_label, seat_number;
```

### CMD-12 - Configure the restricted application role

Run as administrator. Replace the example password with a unique password
before execution; use a new account with no other privileges.

```sql
SOURCE sql/application_role.sql;
CREATE USER 'movie_app'@'localhost' IDENTIFIED BY 'REPLACE_WITH_UNIQUE_PASSWORD';
GRANT 'movie_booking_client' TO 'movie_app'@'localhost';
SET DEFAULT ROLE 'movie_booking_client' TO 'movie_app'@'localhost';
SHOW GRANTS FOR 'movie_app'@'localhost';
```

In a new connection authenticated as movie_app, run:

```sql
SELECT CURRENT_ROLE();
```

The result should include movie_booking_client. Role creation alone does not
assign or activate the role for an account.

### CMD-13 - Install optional expiry scheduler objects

```sql
SOURCE sql/expiry_event.sql;
```

### CMD-14 - Enable automatic expiry

```sql
SET GLOBAL event_scheduler = ON;
ALTER EVENT movie_seat_booking.release_expired_holds ENABLE;
```

### CMD-15 - Run the 20 standard verification checks

Use a separately configured, running test MySQL server. The runner does not
start or install a server. Port 13307 is an example test endpoint, not a server
provided by this repository. Set --port to your test server's actual port.
Test credentials need schema/routine/event creation, account/grant administration
and access to performance_schema.data_lock_waits. The suite creates isolated
schemas and leaves them for inspection. Use an isolated test server.

From the repository root (assuming root needs no password on that test server;
use CMD-16 for saved credentials):

```powershell
python sql/tests/verify_bcnf.py --port 13307 --attempts 1000 --workers 64 --benchmark-requests 1000
```

The test script defaults to this Windows MySQL binary:

```text
C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe
```

Use another binary when required:

```powershell
python sql/tests/verify_bcnf.py `
  --mysql "C:\path\to\mysql.exe" `
  --port 3306 `
  --attempts 1000 `
  --workers 64 `
  --benchmark-requests 1000
```

### CMD-16 - Run using a saved MySQL login path

Create a login path using mysql_config_editor for your test server, then use
matching --user and --port arguments. The runner explicitly sets host, port and
user, overriding those saved fields; it still uses the saved password.
This example uses the root test account:

```powershell
python sql/tests/verify_bcnf.py `
  --login-path localtest `
  --user root `
  --port 13307 `
  --attempts 1000 `
  --workers 64 `
  --benchmark-requests 1000
```

Passwords are not stored in this repository.

### CMD-17 - Run all 21 checks, including automatic expiry

First enable the server-wide scheduler on an isolated test server:

```sql
SET GLOBAL event_scheduler = ON;
```

Then run (add --login-path and --user when required for authentication):

```powershell
python sql/tests/verify_bcnf.py `
  --port 13307 `
  --attempts 1000 `
  --workers 64 `
  --benchmark-requests 1000 `
  --test-event
```

The test changes the generated test event to a one-second schedule temporarily and disables it afterwards. The production event remains a one-minute schedule.

### CMD-18 - Read the recorded JSON result

```powershell
Get-Content sql/tests/bcnf-results.json
```

or:

```bash
cat sql/tests/bcnf-results.json
```

---

## 6. P1 - Database Design

The P1 schema contains **11 BCNF base tables**.

| # | Table | Main attributes | Key / purpose |
|---:|---|---|---|
| 1 | `theatres` | `theatre_id`, `theatre_name`, `address` | Theatre master |
| 2 | `screens` | `screen_id`, `theatre_id`, `screen_name` | Screens inside a theatre; unique theatre/screen name |
| 3 | `movies` | `movie_id`, `title`, `duration_minutes` | Movie catalogue |
| 4 | `seats` | `seat_id`, `screen_id`, `row_label`, `seat_number` | Physical screen seating layout |
| 5 | `shows` | `show_id`, `movie_id`, `screen_id`, `starts_at`, `ticket_price` | Movie schedule; unique screen/start time |
| 6 | `users` | `user_id`, `full_name`, `email` | Booking customers; unique email |
| 7 | `bookings` | user/show reference, booking reference, status, hold deadline, total | Booking lifecycle |
| 8 | `show_seats` | screen/start/row/number | Valid inventory for each scheduled show; primary-key row acts as the seat mutex |
| 9 | `seat_allocations` | booking/row/number | Current ownership for held/confirmed bookings |
| 10 | `booking_seats` | booking/row/number/purchase price | Historical booking items and purchase price |
| 11 | `payment_events` | provider/event/booking/type/amount/status/timestamps | Idempotent payment-event processing |

### Sample fixture summary

| Table | Rows in P1 fixture | Example |
|---|---:|---|
| `theatres` | 2 | Starlight Cinema; Moonlight Cinema |
| `screens` | 3 | Two screens at theatre 1; one at theatre 2 |
| `movies` | 3 | Journey to the Stars; The Last Train; Ocean of Dreams |
| `seats` | 8 | A1/A2/B1/B2 and A1/A2 layouts |
| `shows` | 10 | Fixed fixtures from 2026-09-28 to 2026-10-04 |
| `users` | 2 | Asha Rao; Ravi Kumar |
| `bookings` | 1 | Confirmed booking for INR 400 |
| `show_seats` | 36 | Valid positions generated for fixture shows |
| `seat_allocations` | 2 | Booking 1 owns A1/A2 |
| `booking_seats` | 2 | A1/A2 at INR 200 each |
| `payment_events` | 1 | `demo_provider / evt_demo_001`, applied |

The complete executable schema and fixture rows are in [`sql/p1.sql`](sql/p1.sql).

---

## 7. Normalization

### 1NF

- Every stored field contains one atomic value.
- Seats and payment events are separate rows.
- A booking does not store a comma-separated list of seats.
- JSON is used only as input to `hold_seats`; it is not stored as a repeating group in the relational model.

### 2NF

- Non-key attributes depend on the entire candidate key.
- Example: `booking_seats.purchase_price` depends on `(booking_id, row_label, seat_number)`.
- `show_seats` and `seat_allocations` contain only key attributes.

### 3NF

- Non-key attributes do not determine other non-key attributes inside the same relation.
- Theatre facts stay in `theatres`, movie facts stay in `movies`, and booking lifecycle facts stay in `bookings`.

### BCNF

Every documented non-trivial functional dependency has a candidate key or superkey as its determinant.

Examples of enforced alternate keys:

```text
screens      -> (theatre_id, screen_name)
seats        -> (screen_id, row_label, seat_number)
shows        -> (screen_id, starts_at)
users        -> email
bookings     -> booking_reference
payment_events -> (provider, provider_event_id)
```

The complete candidate-key and functional-dependency analysis is in [`SCHEMA_DESIGN.md`](SCHEMA_DESIGN.md).

---

## 8. P2 - Theatre/Date Showtime Query

Default inputs:

```sql
SET @theatre_id = 1, @selected_date = DATE('2026-09-28');
```

Query:

```sql
SELECT m.title AS movie_title,
       sc.screen_name,
       DATE(sh.starts_at) AS show_date,
       TIME(sh.starts_at) AS show_time
FROM movie_seat_booking.shows AS sh
JOIN movie_seat_booking.movies AS m
  ON m.movie_id = sh.movie_id
JOIN movie_seat_booking.screens AS sc
  ON sc.screen_id = sh.screen_id
JOIN movie_seat_booking.theatres AS th
  ON th.theatre_id = sc.theatre_id
WHERE th.theatre_id = @theatre_id
  AND sh.starts_at >= @selected_date
  AND sh.starts_at < DATE_ADD(@selected_date, INTERVAL 1 DAY)
ORDER BY m.title, sh.starts_at, sh.show_id;
```

Expected default output:

| Movie | Screen | Date | Time |
|---|---|---|---|
| Journey to the Stars | Screen 1 | 2026-09-28 | 10:00:00 |
| Journey to the Stars | Screen 1 | 2026-09-28 | 14:00:00 |
| The Last Train | Screen 2 | 2026-09-28 | 11:00:00 |

The half-open range:

```sql
sh.starts_at >= @selected_date
AND sh.starts_at < DATE_ADD(@selected_date, INTERVAL 1 DAY)
```

keeps a function off `starts_at`, includes the complete selected day, and excludes the following midnight.

---

## 9. Booking and Concurrency Design

### 9.1 Seat hold flow

```text
Request seats
   |
   v
Validate request + show
   |
   v
Create held booking
   |
   v
Lock requested show_seats rows in canonical row/number order
   |
   v
Re-check current ownership
   |
   +-- unavailable/invalid --> ROLLBACK complete request
   |
   v
Insert seat_allocations + booking_seats
   |
   v
COMMIT
```

### 9.2 Why pessimistic locking is used

The transaction API uses InnoDB `SELECT ... FOR UPDATE` on each requested `show_seats` row.

The inventory row becomes the **mutex** for that show-seat. A competing transaction waits and then checks committed ownership before inserting its allocation.

Advantages for this project:

- prevents two concurrent bookings from owning the same show-seat;
- multi-seat holds are all-or-nothing;
- works cleanly with the normalized ownership model;
- makes the integrity boundary explicit and testable.

Trade-offs:

- hot seats cause lock waits;
- lock timeouts/deadlocks must be retried at the complete-call boundary;
- high contention reduces throughput.

An optimistic design would require versioned claim state or a dedicated unique show-seat claim relation, which would change the current schema/integrity boundary.

### 9.3 Transaction rules

Public routines:

```text
hold_seats(...)
confirm_payment(...)
expire_booking(...)
```

use these rules:

- `READ COMMITTED` isolation;
- public routines own their transactions;
- every SQL exception rolls back;
- inventory is locked in canonical seat order;
- clients retry only MySQL **1205** (lock timeout) and **1213** (deadlock);
- retries restart the **whole call** with bounded backoff/jitter;
- business rejections such as unavailable seats are not retried;
- expiry is evaluated using `SYSDATE()` after lock waits.

Call routines outside an existing transaction. Keep sysdate-is-now disabled;
use row-based binary logging when replicating these routines.

### 9.4 Payment idempotency

`payment_events` enforces:

```text
UNIQUE (provider, provider_event_id)
```

`confirm_payment` locks the booking and payment event and verifies:

- event belongs to the same booking;
- event amount matches;
- event type matches;
- booking is still live;
- held seats are still completely owned;
- paid amount equals booking/item totals.

Behavior:

- identical replay -> returns the existing outcome;
- altered replay -> rejected as `event payload mismatch`;
- late or extra successful payment -> `refund_required`;
- no external refund API is called by this SQL-only project.

---

## 10. Automatic Hold Expiry

Manual cleanup for the booking captured in CMD-10 uses:

```sql
CALL expire_booking(@expiry_booking);
```

Optional scheduled cleanup uses `sql/expiry_event.sql`.

When enabled, the event:

- runs every minute;
- considers at most 100 expired bookings per pass;
- uses the same booking/inventory lock protocol as payment confirmation;
- uses a named lock to prevent overlapping sweeps in the same database;
- skips busy bookings after a short lock timeout and retries them on a later pass;
- preserves confirmed bookings;
- uses an expiry index for candidate selection.

For restart persistence, configure event_scheduler=ON in the server configuration.
Keep the event definer account and its required privileges available.

Automatic release is **eventual**, not guaranteed to occur at the exact expiry second. Payment confirmation still checks the real deadline, so delayed cleanup cannot make a late payment valid.

---

## 11. Application Permission Boundary

The intended application account should not write tables directly.

CMD-12 installs the role, assigns it to a new account and activates it by default.

Do **not** grant:

```text
INSERT / UPDATE / DELETE on the base tables
EXECUTE on lock_booking_inventory
EVENT privilege to the application account
```

The verification suite confirms a restricted client can successfully call the public hold routine but cannot bypass the integrity boundary with raw DML or the internal helper.

---

## 12. Test Case Index

The automated suite creates a new isolated schema named `bcnf_verify_<guid>` and does not drop or overwrite the application database.

| ID | Test case | What is verified | Recorded result |
|---|---|---|---|
| TC-01 | Fresh BCNF schema and routines install | `p1.sql` + booking API install cleanly in an isolated schema | PASS |
| TC-02 | Sample allocations and item ownership | Fixture ownership satisfies integrity invariants | PASS |
| TC-03 | Inventory contains only candidate-key attributes | `show_seats` contains only screen/start/row/number | PASS |
| TC-04 | Nine constraint rejection cases | FK, unique and CHECK constraints reject invalid writes | PASS |
| TC-05 | P2 exact default output | Theatre 1 / 2026-09-28 returns exactly 3 expected rows | PASS |
| TC-06 | P2 alternate theatre/date and empty result | Alternate filters and a no-show date return correct results | PASS |
| TC-07 | P2 day boundaries | 00:00:00 and 23:59:59 included; next midnight excluded | PASS |
| TC-08 | Invalid seat / duplicate request / past show | Invalid booking attempts are rejected without corrupting invariants | PASS |
| TC-09 | Nine malformed seat values | Bad JSON seat values are rejected before coercion | PASS |
| TC-10 | Overlapping two-seat contention | 1,000 contenders for the same seats produce one winner | PASS |
| TC-11 | Losing holds roll back completely | No partial booking/allocation remains for losing transactions | PASS |
| TC-12 | Independent-seat throughput | 1,000 distinct-seat holds succeed under 64 workers | PASS |
| TC-13 | 100 concurrent duplicate confirmations | Same provider event is applied once logically; all callers see stable outcome | PASS |
| TC-14 | Replayed event payload mismatch | Same provider/event ID with changed amount is rejected | PASS |
| TC-15 | 30 expiry/payment races | Expiry and payment serialize safely; stale payment cannot reclaim replacement seat | PASS |
| TC-16 | Hold expires while payment waits | Expiry clock is evaluated after the lock wait | PASS |
| TC-17 | Lock timeout rollback + retry | 1205 leaves no partial booking; full-call retry succeeds | PASS |
| TC-18 | Real deadlock victim + retry | 1213 is observed and the whole transaction is retried successfully | PASS |
| TC-19 | Restricted client boundary | Public routine works; raw DML/internal helper are denied | PASS |
| TC-20 | Optional expiry event installs disabled | Installation does not silently enable automatic cleanup | PASS |
| TC-21 | Scheduler automatic expiry | Expired hold is released while live hold and sold seats are preserved | PASS |

### TC-04 constraint cases

The suite intentionally verifies these rejections:

```text
1. Invalid theatre foreign key for a screen
2. Duplicate show-seat inventory row
3. Invalid physical seat/show inventory combination
4. Allocation referencing an unknown booking
5. Duplicate allocation for a booking seat
6. Held booking without hold_expires_at
7. Negative booking-seat purchase price
8. Duplicate payment provider/event identity
9. Processed payment event with invalid processed_at state
```

### TC-09 malformed seat values

The suite rejects malformed request values such as:

```text
fractional seat number
string instead of integer
row label longer than 5 characters
empty row label
seat number 0
seat number > 65535
null row
missing seat number
boolean used as a seat number
```

### Core invariant checked repeatedly

The suite asserts there are no:

```text
duplicate show-seat owners
allocations outside valid show inventory
inactive bookings still owning seats
partial active bookings
lost booking-seat items
multiple applied successful payments for one booking
```

---

## 13. Verified Results and Benchmarks

Recorded execution environment:

```text
MySQL version: 8.4.9
Worker threads: 64
Contention attempts: 1000
Independent-seat benchmark requests: 1000
Event execution test: enabled and passed
Overall result: PASS
Checks passed: 21 / 21
```

### 13.1 Hot-seat contention

```text
Requests: 1000
Workers: 64
Seats requested per contender: 2
Successful holds: 1
Rejected contenders: 999
Elapsed: 21.313 seconds
Partial losing bookings: 0
```

This verifies the correctness property: **one winner, no double-booking, no partial losing hold**.

### 13.2 Independent-seat local throughput baseline

```text
Requests: 1000
Workers: 64
Successful holds: 1000
Failures: 0
Elapsed: 20.06 seconds
Throughput: 49.85 requests/second
p50 latency: 1126.653 ms
p95 latency: 1809.963 ms
p99 latency: 2416.709 ms
max latency: 2941.677 ms
```

### 13.3 Payment / expiry concurrency

```text
Concurrent duplicate confirmations: 100
Result: one stable applied outcome

Expiry/payment race cases: 30
Expired cases: 15
Live cases: 15
Result: stale confirmation cannot take seats from replacement booking
```

> These performance figures are a **reproducible local baseline**, not production-capacity certification. The benchmark uses 64 worker threads, not 1,000 simultaneous database connections, and each request launches a MySQL CLI process/TCP connection, so local process and connection startup overhead is included.

### Recorded report

See:

```text
sql/tests/bcnf-results.json
```

---

## 14. Troubleshooting

### `mysql` is not recognized

Use the full executable path:

```powershell
& "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe" -u root -p
```

or pass it to the test runner:

```powershell
python sql/tests/verify_bcnf.py --mysql "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe"
```

### Test runner cannot connect

Confirm:

```sql
SELECT VERSION();
```

and verify the configured port. The verification script defaults to:

```text
127.0.0.1:13307
```

Change it if your server uses `3306`:

```powershell
python sql/tests/verify_bcnf.py --port 3306
```

### P1 fails with duplicate rows/tables

`p1.sql` is designed for a fresh project database. Use a clean database for installation. The automated verification suite creates its own isolated schema.

### Automatic event test does not run

Check:

```sql
SELECT @@GLOBAL.event_scheduler;
```

For the optional automated event check, the scheduler must already be `ON` on the isolated test server before using:

```text
--test-event
```

### Application account receives permission errors

That is expected for raw DML and the internal helper. The restricted client should use only:

```text
SELECT
CALL hold_seats(...)
CALL confirm_payment(...)
CALL expire_booking(...)
```

### Lock timeout or deadlock occurs

Only errors **1205** and **1213** should be retried automatically, with bounded backoff/jitter. Restart the complete public routine call; do not continue a partially failed transaction.
