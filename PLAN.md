# Movie theatre booking - Project requirements and plan

## Scenario

A movie-ticket booking platform lets a customer select a theatre, choose one of
the next seven dates, and view the movies and show timings for that date.
Multiple customers may attempt to book the same seats simultaneously. The data
model must support temporary holds, safe confirmation and release of expired holds.

## Objective and scope

Build the MySQL P1 and P2 solution with documented entities, normalized tables,
sample data, executable queries and reproducible concurrency tests. Include
transaction routines for seat holds and payment confirmation, plus an optional
MySQL event for automatic expiry.

The broader ticketing scenario introduces Redis, queues and a backend service.
This project's agreed scope is the SQL layer and its verification. A frontend,
HTTP webhook endpoint, provider signature verification, external refund execution,
Redis integration, queue processing and distributed failover are outside this
implementation scope.

## P1 requirements: Schema and booking integrity

- Identify all entities, attributes, relationships and business rules.
- Define primary keys, candidate keys, foreign keys, unique constraints,
  validation constraints and indexes.
- Explain 1NF, 2NF, 3NF and BCNF using candidate keys and functional dependencies.
- Separate physical seats, per-show inventory, current allocations and historical
  booking items so ownership changes do not erase purchase history.
- Provide directly executable MySQL table definitions and representative sample rows.
- Prevent double-booking and partial multi-seat holds under concurrent requests.
- Store hold ownership and deadlines; reject confirmations after expiry.
- Process duplicate payment events idempotently and reject changed replay payloads.
- Ensure late payment events cannot reclaim seats assigned to another booking.
- Provide timer-based expiry using an optional MySQL event with documented activation.
- Restrict application writes to the public transaction routines.

### Proposed entities

| Entity | Purpose |
| --- | --- |
| theatres | Theatre identity and address |
| screens | Screens within a theatre |
| seats | Physical seat positions within a screen |
| movies | Movie titles and durations |
| shows | Movie screenings, start times and prices |
| users | Customer identity and contact information |
| bookings | Customer, selected show, lifecycle state, hold deadline and total |
| show_seats | Valid seat inventory for each show |
| seat_allocations | Current seat ownership through a booking |
| booking_seats | Historical purchased seat positions and prices |
| payment_events | Provider event identities and processing outcomes |

## P2 requirements: Theatre and date query

Accept a theatre ID and selected date. Return movie title, screen name, show
date and show time for every matching show, in a deterministic order.
Use an inclusive day start and exclusive next-day start to handle midnight
correctly and keep the show-start column usable by an index.

Provide sample data spanning seven dates, multiple theatres and screens,
multiple showtimes for one movie, and dates with no matching shows. Describe
the date-picker behavior as today plus six days in Indian local time.

## Implementation approach

1. Define the business assumptions, entities, candidate keys and dependencies.
2. Create the normalized InnoDB schema, constraints, indexes and sample inserts.
3. Implement atomic hold, confirmation and expiry routines. Lock inventory in
   a consistent order and roll back the entire request on failure.
4. Enforce payment replay checks, amount validation, ownership checks and hold
   deadlines within the transaction. Return an explicit outcome for payments
   requiring external reconciliation.
5. Add restricted application privileges and optional scheduled expiry using
   the same locking protocol as confirmation.
6. Implement the theatre/date query and document expected sample output.
7. Build and run isolated integration and concurrency tests. Record measured
   results and document the environment and limits of the evidence.
8. Prepare the schema documentation, execution instructions and GitHub PR.

Compare pessimistic row locking with optimistic claims and explain the chosen
strategy. Keep transactions short, use a consistent lock order, and retry
transient deadlock or lock-timeout failures at the full-transaction boundary.
Assume show schedules and seat layouts remain stable while sales operate.

## Verification and acceptance criteria

| Area | Required verification |
| --- | --- |
| Installation | Schema, sample data and routines execute on a clean MySQL database |
| Constraints | Invalid references, duplicate keys and invalid values are rejected |
| Seat input | Malformed, duplicate and out-of-show seat requests are rejected without partial writes |
| P2 | Exact sample results, theatre/date isolation, empty results and midnight boundaries |
| Contention | Competing requests cannot own the same show-seat; losing multi-seat requests roll back completely |
| Lifecycle | Expiry and confirmation races preserve ownership; stale confirmations cannot reclaim seats |
| Payments | Concurrent duplicate events produce one applied effect; altered replays are rejected |
| Recovery | Lock timeouts and deadlocks allow safe whole-transaction retries |
| Permissions | Application accounts can use public routines but cannot bypass them with direct writes |
| Scheduling | Enabled expiry releases expired holds while preserving live holds and confirmed seats |
| Load | Measure contested and independent-seat workloads, successes, rejections, throughput and latency |

Design the load test with at least 1,000 requests and a documented worker limit.
Record actual simultaneous concurrency rather than equating request count with
open connections. Assert no duplicate ownership, lost allocations, partial
active bookings or duplicate applied payment effects. Use isolated test schemas
and report local measurements without treating them as proof of production scale.

## Deliverables

- README with setup instructions, sample rows, P1/P2 usage and scope.
- Schema document listing attributes, relationships, keys and normalization reasoning.
- Executable SQL for P1, P2, booking routines, application privileges and optional expiry.
- Reproducible test suite and an execution report containing actual results.
- GitHub pull request containing the documentation, SQL and verification artifacts.

## Technical assumptions

Use MySQL 8.0.16 or newer with InnoDB, Indian local time and INR amounts.
Use Python and the MySQL CLI for isolated testing. Document scheduler activation,
required privileges, cleanup delays and transaction ownership. Keep credentials
out of the repository and avoid modifying an application database during tests.
