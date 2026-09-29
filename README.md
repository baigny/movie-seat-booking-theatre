# Movie theatre booking — P1 and P2

Repository: [baigny/movie-seat-booking-theatre](https://github.com/baigny/movie-seat-booking-theatre).
The complete solution is on [feature/p1-p2-sql](https://github.com/baigny/movie-seat-booking-theatre/tree/feature/p1-p2-sql).

Executable MySQL schema, sample data, showtime query, and transaction tests.
The schema follows **BCNF** and includes **concurrency verification**.
Redis, queues, an HTTP backend, and external payment integration
are outside the project's scope.
Automatic hold release is available through an optional MySQL event.

## Files

- [P1](sql/p1.sql): eleven BCNF base tables, constraints, indexes, sample data.
- [Schema design](SCHEMA_DESIGN.md): every attribute, relationships, candidate
  keys, functional dependencies, and the integrity boundary.
- [Transaction API](sql/booking_api.sql): atomic holds, confirmation, expiry,
  and the derived seat_availability view.
- [P2](sql/p2.sql): theatre/date showtime query.
- [Optional expiry event](sql/expiry_event.sql): bounded timer-based cleanup using the transaction API.
- [Test suite](sql/tests/verify_bcnf.py) and [execution report](sql/tests/bcnf-results.json).

## Installation

MySQL 8.0.16+ with InnoDB; tested on Community Server 8.4.9. Dates use Indian
local time; money is INR. On a fresh project database, at the mysql prompt:

```sql
SET time_zone = '+05:30';
SOURCE C:/movie-seat-booking-theatre/sql/p1.sql;
SOURCE C:/movie-seat-booking-theatre/sql/booking_api.sql;
SOURCE C:/movie-seat-booking-theatre/sql/p2.sql;
```

Install P1 only in a fresh database. Do not source it against populated tables.
Verification runs create isolated schemas and do not modify an application database.

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
are never expired. An external worker or the optional MySQL event can call it.

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

The API chooses pessimistic seat-row locks for contested inventory. The trade-off
with an optimistic claim design, including the unique-claim/version state that
would be needed with this normalized schema, is documented in
[SCHEMA_DESIGN.md](SCHEMA_DESIGN.md).

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

## Optional automatic hold release

After installing the transaction API, an administrator can install the event once:

```sql
SOURCE C:/movie-seat-booking-theatre/sql/expiry_event.sql;
-- Server-wide setting: enable deliberately on the intended server.
SET GLOBAL event_scheduler = ON;
ALTER EVENT movie_seat_booking.release_expired_holds ENABLE;
```

Installation leaves the event disabled and does not change the server-wide
scheduler setting. Configure event_scheduler=ON in the server configuration for
persistence across restarts. Keep the installer/definer account available with
the required privileges. Application accounts do not receive EVENT or access to
the sweep procedure. To pause cleanup, ALTER EVENT with DISABLE.

The event runs every minute, considers at most 100 expired bookings per pass,
and calls expire_booking for each. An expiry index supports candidate selection;
a named lock prevents overlapping sweeps in the same database. Busy bookings
are skipped after a short lock timeout and retried on a later pass. Confirmation
still checks the real deadline, so delayed cleanup cannot authorize late payment.
Release is eventual, not exact to the second; backlog and lock waits can increase
the delay. Monitor expired-held counts, event LAST_EXECUTED and the server error
log. A single-server event does not supply distributed failover orchestration.

## Requirements coverage

| Requirement | Implementation and evidence |
| --- | --- |
| P1 entities, attributes, sample rows and executable SQL | sql/p1.sql, sample rows above, and SCHEMA_DESIGN.md |
| 1NF, 2NF, 3NF and BCNF | Explicit normal-form reasoning and candidate-key dependencies in SCHEMA_DESIGN.md |
| Seat locking, no double-booking or lost holds | Atomic routines, restricted application role, contention and lifecycle invariants in the test suite |
| Timer-based hold release | Optional MySQL event; activation requires administrator setup |
| Idempotent payment handling | SQL confirmation routine and concurrent replay tests; no HTTP webhook endpoint or provider signature verification |
| P2 theatre/date showtimes | sql/p2.sql; exact fixture results, alternate filters and midnight boundary tests |
| Load and concurrency evidence | Local 1,000-request workloads at 64 workers, race tests and recorded latency; not a production-scale certification |
| GitHub PR submission | [PR #1](https://github.com/baigny/movie-seat-booking-theatre/pull/1) |

This submission covers the MySQL data model, booking transactions, showtime
query, optional scheduled expiry, and reproducible database tests.

## Verified concurrency evidence

The [report](sql/tests/bcnf-results.json) records a successful MySQL 8.4.9 run:

- 1,000 competing two-seat requests at 64 workers: one winner, 999 rejected in
  21.313 seconds; no partial losing bookings or allocations.
- Independent-seat workload: 1,000 of 1,000 holds succeeded at 64 workers in
  20.06 seconds (49.85 requests/second). Latency was p50 1,127 ms, p95 1,810 ms,
  p99 2,417 ms, and max 2,942 ms.
- 100 concurrent duplicate confirmations: one applied event and stable ownership.
- 30 overlapping expiry/payment races: 15 expired and 15 live holds; stale
  confirmation cannot take seats from a replacement booking.
- Expiry while waiting for a lock, timeout rollback/retry, and an actual
  deadlock victim followed by whole-transaction retry all passed.
- Nine negative constraint cases, invalid/duplicate seat requests,
  malformed JSON seat values, P2 filters and midnight boundaries,
  and restricted-client access passed.
  The optional event installed disabled; an enabled test event automatically
  expired a hold while preserving live holds and confirmed seats.

All 21 checks in the execution report passed.

The suite asserts no duplicate show-seat ownership, no invalid inventory,
no partial active bookings, no lost allocations, and no duplicate applied
payment effects. Lock waits are observed in performance_schema. The benchmark
used 64 worker threads, not 1,000 simultaneous connections. It launches one
MySQL CLI process and TCP connection per request, so measurements include local
process and connection startup overhead. Treat these figures as a reproducible
local baseline, not production capacity or a universal comparison with an
unimplemented optimistic strategy.

## Reproduce

Use Python 3.12 and mysql CLI against an isolated test server:

```powershell
python sql/tests/verify_bcnf.py --port 13307 --attempts 1000 --workers 64 --benchmark-requests 1000
```

Only the Python standard library is needed. Use --login-path for saved local
credentials. The suite creates GUID-named schemas and leaves them for inspection;
it never drops or overwrites an application database. Administrative test access
is required to create routines, observe locks, and create/remove a temporary
restricted account. Passwords are not stored in this repository.

The integration suite and its JSON report provide the execution evidence.
For the automatic-event check, enable event_scheduler on the isolated test
server first and add --test-event. This flag uses a one-second schedule in the
generated schema, then disables that event. The production script uses one minute.
