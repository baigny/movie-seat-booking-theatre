# BCNF schema review

The [P1 schema](sql/p1.sql) contains eleven base tables.
Valid show inventory and current ownership are separate relations. No base
table repeats the show determined by an allocation's booking.

## Attributes and constraints

All columns are NOT NULL unless marked nullable. Integer IDs and seat numbers
are UNSIGNED. All tables use InnoDB; foreign keys use RESTRICT on update/delete.
Money is INR. Text defaults to utf8mb4_0900_ai_ci; payment identifiers use ascii_bin.

| Table | Attributes and types | Keys / rules |
| --- | --- | --- |
| theatres | theatre_id INT; theatre_name VARCHAR(150); address VARCHAR(500) | Auto-increment PK theatre_id |
| screens | screen_id INT; theatre_id INT; screen_name VARCHAR(50) | Auto-increment PK screen_id; unique theatre/name; theatre FK |
| movies | movie_id INT; title VARCHAR(200); duration_minutes SMALLINT | Auto-increment PK movie_id; positive duration |
| seats | seat_id INT; screen_id INT; row_label VARCHAR(5); seat_number SMALLINT | Auto-increment PK seat_id; unique screen/row/number; screen FK; positive number |
| shows | show_id INT; movie_id INT; screen_id INT; starts_at DATETIME; ticket_price DECIMAL(10,2) | Auto-increment PK show_id; unique screen/start; movie/screen FKs; nonnegative price |
| users | user_id INT; full_name VARCHAR(150); email VARCHAR(254) | Auto-increment PK user_id; unique email |
| bookings | booking_id INT; user_id INT; screen_id INT; starts_at DATETIME; booking_reference CHAR(36); status ENUM; created_at DATETIME; hold_expires_at DATETIME nullable; total_amount DECIMAL(10,2) | Auto-increment PK booking_id; unique reference; user FK; screen/start FK to shows; nonnegative amount; held requires deadline |
| show_seats | screen_id INT; starts_at DATETIME; row_label VARCHAR(5); seat_number SMALLINT | All four columns form PK; show FK on screen/start; physical-seat FK on screen/row/number |
| seat_allocations | booking_id INT; row_label VARCHAR(5); seat_number SMALLINT | All three columns form PK; booking FK; positive number |
| booking_seats | booking_id INT; row_label VARCHAR(5); seat_number SMALLINT; purchase_price DECIMAL(10,2) | PK booking/row/number; booking FK; positive number; nonnegative historical price |
| payment_events | payment_event_id BIGINT; provider VARCHAR(50); provider_event_id VARCHAR(191); booking_id INT; event_type ENUM; amount DECIMAL(10,2); processing_status ENUM; received_at DATETIME; processed_at DATETIME nullable | Auto-increment PK event ID; unique provider/event; booking FK; nonnegative amount; pending iff processed_at is NULL |

Booking statuses: held (default), confirmed, expired, cancelled, payment_failed.
created_at defaults to CURRENT_TIMESTAMP. Event types: payment_succeeded,
payment_failed, refund_succeeded. Processing states: pending (default), applied,
ignored, refund_required. received_at defaults to CURRENT_TIMESTAMP.

## Relationships and indexes

A theatre has many screens; a screen has many physical seats and shows; each
show has one movie. Bookings reference a customer and the show's unique
(screen_id, starts_at) key. Inventory lists valid seats per show. Allocations
derive their show through bookings. Historical booking items survive expiry
while current allocations are released. A booking can have many payment events.

Foreign keys and unique keys have supporting indexes. bookings also indexes
(user_id, created_at); payment_events indexes (booking_id, received_at).
The inventory primary key is the seat mutex. The shows screen/start key
supports P2. Allocation checks join the show's bookings to their allocations
through booking-leading keys. This normalized join has a cost; the report
measures correctness locally rather than claiming production throughput.

## Functional dependencies and normal forms

Addresses, names, prices, dates, and statuses are atomic display/business
values (1NF). Names/titles/addresses are not assumed unique. Prices do not
depend on movie alone. Email equality follows its collation. Historical item
prices may differ within a booking, for example through discounts.

| Relation | Candidate keys | Nontrivial dependencies |
| --- | --- | --- |
| theatres | theatre_id | ID determines name/address |
| screens | screen_id; theatre_id/screen_name | Either key determines all attributes |
| movies | movie_id | ID determines title/duration |
| seats | seat_id; screen_id/row_label/seat_number | Either key determines all attributes |
| shows | show_id; screen_id/starts_at | Either key determines movie/price and other key columns |
| users | user_id; email | Either key determines all attributes |
| bookings | booking_id; booking_reference | Either key determines user, show, lifecycle facts and total |
| show_seats | screen_id/starts_at/row_label/seat_number | All-key relation; no additional nontrivial dependencies |
| seat_allocations | booking_id/row_label/seat_number | All-key relation; no additional nontrivial dependencies |
| booking_seats | booking_id/row_label/seat_number | Complete key determines historical purchase_price |
| payment_events | payment_event_id; provider/provider_event_id | Either key determines all event facts |

Every nontrivial determinant is a candidate key or superkey under these stated
dependencies. Thus each base relation satisfies BCNF, and consequently 3NF and
2NF, in addition to the atomic-value 1NF assumptions. Nullable timestamps
represent absent lifecycle values; they do not introduce a non-key determinant.

seat_allocations stores booking and seat identifiers. Show coordinates
exist in bookings, where booking_id is a key. Ownership status is derived from
bookings instead of being stored per seat. seat_availability is a joined view,
not a base table, and does not reintroduce stored redundancy.

## Integrity boundary

Unique ownership across different bookings is enforced by the transaction API
under an inventory-row lock, rather than by duplicating show coordinates in
the allocation key. The API also validates inventory membership, complete
item ownership, amount equality, and expiry. All failed holds roll back the
entire request. Applications must have only SELECT and EXECUTE on the public
routines, with no direct table DML and no access to the internal lock helper.
The suite tests this privilege boundary. Administrators can bypass business
rules through direct DML and are outside the client guarantee.

Show schedules/layouts must remain stable while sales operate. Administrative
rescheduling, external refunds, scheduling a cleanup worker, Redis, and queues
are outside the project's scope. Concurrency correctness is documented with the
actual test counts and limits in [README](README.md), not inferred from BCNF.
