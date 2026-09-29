# Movie theatre booking — P1 and P2

Repository: [baigny/movie-seat-booking-theatre](https://github.com/baigny/movie-seat-booking-theatre).
The complete solution is on [feature/p1-p2-sql](https://github.com/baigny/movie-seat-booking-theatre/tree/feature/p1-p2-sql).

Executable MySQL schema, sample data, showtime query, and transaction tests.
The schema follows **BCNF** and includes **concurrency verification**.
Redis, queues, an HTTP backend, external payments, and automatic scheduling
are outside the project's scope.

## Files

- [P1](sql/p1.sql): eleven BCNF base tables, constraints, indexes, sample data.
- [Schema review](SCHEMA_REVIEW.md): every attribute, relationships, candidate
  keys, functional dependencies, and the integrity boundary.
- [Transaction API](sql/booking_api.sql): atomic holds, confirmation, expiry,
  and the derived seat_availability view.
- [P2](sql/p2.sql): theatre/date showtime query.
- [Test suite](sql/tests/verify_bcnf.py) and [execution report](sql/tests/bcnf-results.json).
- [Migration](sql/migrations/001_bcnf_allocations.sql): allocation-table conversion for compatible existing databases.

## Installation

MySQL 8.0.16+ with InnoDB; tested on Community Server 8.4.9. Dates use Indian
local time; money is INR. On a fresh project database, at the mysql prompt:

```sql
SET time_zone = '+05:30';
SOURCE C:/data-modelling-movie-theatre/sql/p1.sql;
SOURCE C:/data-modelling-movie-theatre/sql/booking_api.sql;
SOURCE C:/data-modelling-movie-theatre/sql/p2.sql;
```

Do not source P1 against populated tables. For a compatible existing database,
back it up, stop application writes, run the migration once, then install
booking_api.sql. Use mysql batch input that aborts on errors, without --force;
DDL commits implicitly, so inspect a partially failed migration rather than
rerunning blindly. Migration preflight rejects inconsistent allocations.
Migration and routine installation were verified against the compatible
sample schema; verification runs do not modify your existing database.

Applications must use the grants in [application_role.sql](sql/application_role.sql):
SELECT plus EXECUTE on hold_seats, confirm_payment, and expire_booking only.
Assign the role to a new application account with no other privileges. Do not
grant table DML or the internal lock helper. Each public routine owns its
transaction and must be called outside an existing transaction.

## Sample rows

| Table | Rows | Example |
| --- | --- | --- |
| theatres | 2 | Starlight Cinema, Bengaluru; Moonlight Cinema, Chennai |
| screens | 3 | Two screens at theatre 1; one at theatre 2 |
| movies | 3 | Journey to the Stars (120 min), The Last Train (105), Ocean of Dreams (135) |
| seats | 8 | Screen 1 A1/A2/B1/B2; screens 2 and 3 A1/A2 |
| shows | 10 | Fixed fixture dates September 28–October 4, 2026 |
| users | 2 | Asha Rao, asha@example.com; Ravi Kumar, ravi@example.com |
| bookings | 1 | Booking 1: user 1, screen 1, September 28 at 10:00, confirmed, INR 400 |
| show_seats | 36 | All valid positions for each fixture show |
| seat_allocations | 2 | Booking 1 owns A1/A2 |
| booking_seats | 2 | Booking 1, A1/A2 at INR 200 each |
| payment_events | 1 | demo_provider / evt_demo_001, INR 400, applied |

Full example values are in P1. The availability view derives two sold seats
and 34 available seats. The historical booking was created September 27 at
18:00, held until 18:10, and paid at 18:05 (processed 18:05:01). Fixture dates
stay fixed; tests create future shows relative to the server clock.

## Transaction behavior

`hold_seats(user_id, show_id, reference, seats_json, ttl_seconds)` takes 1–20
distinct positions and a 1–900 second hold. JSON example:
`[{"row":"B","number":1},{"row":"B","number":2}]`. Inventory locks are taken
in row/number order. Any unavailable/invalid seat rolls back the new booking,
all allocations, and all items. Success returns booking_id. Expired allocations
remain protected until cleanup releases them; a competing hold cannot steal them.

`expire_booking(booking_id)` locks the booking and inventory, releasing only
that booking's allocations when a held deadline has passed. Confirmed bookings
are never expired. An external worker can call it; no scheduler is installed.

`confirm_payment(booking_id, provider, event_id, amount)` serializes with expiry
on the booking lock, checks totals and complete ownership, and confirms once.
Duplicate events return the existing outcome; altered replay payloads are
rejected. Late success or a distinct extra payment returns refund_required
without reclaiming reassigned seats. No external refund is executed.

The clock is evaluated after lock waits using SYSDATE(), rather than NOW()'s
statement-start time. Do not enable sysdate-is-now; use row-based logging if
replicating these routines. Each public routine uses READ COMMITTED. Existing
bookings lock before inventory; inventory uses canonical order. Every SQL
exception rolls back the transaction. Clients retry only 1205 and 1213 with
bounded backoff/jitter, restarting the entire call. Business rejections are not
retried. The suite induces and verifies both a timeout and a real deadlock.

MySQL references: [locking reads](https://dev.mysql.com/doc/refman/8.4/en/innodb-locking-reads.html)
and [JSON_TABLE](https://dev.mysql.com/doc/refman/8.4/en/json-table-functions.html).

## P2 query

P2 uses theatre 1 and September 28, 2026 by default. The WHERE clause uses a
half-open date range without a function on starts_at. Order is movie title,
start time, then show ID.

| Movie | Screen | Time |
| --- | --- | --- |
| Journey to the Stars | Screen 1 | 10:00:00 |
| Journey to the Stars | Screen 1 | 14:00:00 |
| The Last Train | Screen 2 | 11:00:00 |

Theatre 2 that day returns Ocean of Dreams at 10:00. Theatre 1 on September 29
returns The Last Train at 10:00; October 5 has no rows. The intended date picker
offers today plus six days in Indian local time; no frontend is included.
Edit the SET inputs for another selection; sourcing P2 resets its defaults.

## Verified concurrency evidence

The [report](sql/tests/bcnf-results.json) records a successful MySQL 8.4.9 run:

- 1,000 competing two-seat requests at 64 workers: one winner, 999 rejected;
  no partial losing bookings or allocations.
- 100 concurrent duplicate confirmations: one applied event and stable ownership.
- 30 overlapping expiry/payment races: 15 expired and 15 live holds; stale
  confirmation cannot take seats from a replacement booking.
- Expiry while waiting for a lock, timeout rollback/retry, and an actual
  deadlock victim followed by whole-transaction retry all passed.
- Nine negative constraint cases, invalid/duplicate seat requests,
  all four P2 cases, migration preservation, and restricted-client access passed.

All 19 checks in the execution report passed.

The suite asserts no duplicate show-seat ownership, no invalid inventory,
no partial active bookings, no lost allocations, and no duplicate applied
payment effects. Lock waits are observed in performance_schema. This is
local correctness evidence with 64 workers, not 1,000 simultaneous connections
or a claim of production throughput under every possible schedule.

## Reproduce

Use Python 3.12 and mysql CLI against an isolated test server:

```powershell
python sql/tests/verify_bcnf.py --port 13307 --attempts 1000 --workers 64
```

Only the Python standard library is needed. Use --login-path for saved local
credentials. The suite creates GUID-named schemas and leaves them for inspection;
it never drops or overwrites an application database. Administrative test access
is required to create routines, observe locks, and create/remove a temporary
restricted account. Passwords are not stored in this repository. The migration
test uses the `a2153ef` compatibility tag included in the repository.

The integration suite and its JSON report provide the execution evidence.
