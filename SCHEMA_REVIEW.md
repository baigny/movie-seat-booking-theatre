# Schema and normalization review

The executable definition is [sql/p1.sql](sql/p1.sql). README batch sections
contain the dictionaries and example rows for the other eight tables; the
two missing dictionaries are completed here. All amounts are INR. Every table
uses InnoDB; foreign-key update and delete actions are RESTRICT.

## Bookings and inventory dictionary

| Table | Column | Type | Meaning / constraint |
| --- | --- | --- | --- |
| bookings | booking_id | INT UNSIGNED | Auto-increment primary key |
| bookings | user_id | INT UNSIGNED | Required FK to users |
| bookings | screen_id | INT UNSIGNED | Required component of show FK |
| bookings | starts_at | DATETIME | Required component of show FK |
| bookings | booking_reference | CHAR(36) | Required unique reference |
| bookings | status | ENUM | held (default), confirmed, expired, cancelled, payment_failed |
| bookings | created_at | DATETIME | Required, defaults to CURRENT_TIMESTAMP |
| bookings | hold_expires_at | DATETIME | Nullable except when held |
| bookings | total_amount | DECIMAL(10,2) | Required, nonnegative; transaction reconciles with items |
| show_seats | screen_id | INT UNSIGNED | Primary-key component, show/seat/booking FK component |
| show_seats | starts_at | DATETIME | Primary-key component, show/booking FK component |
| show_seats | row_label | VARCHAR(5) | Primary-key component, physical-seat FK component |
| show_seats | seat_number | SMALLINT UNSIGNED | Primary-key component, physical-seat FK component |
| show_seats | status | ENUM | available (default), held, sold |
| show_seats | booking_id | INT UNSIGNED | NULL for available, required for held/sold |

bookings has unique (booking_id, screen_id, starts_at) for the composite
inventory FK and index (user_id, created_at). Its show FK points to the unique
(screen_id, starts_at) in shows. show_seats has indexes on
(screen_id, starts_at, status, row_label, seat_number) and
(booking_id, screen_id, starts_at). MySQL adds any further index required by an
FK. The show-seat primary key prohibits double inventory rows; ownership and
expiry transitions still require transactions.

## Relationships

| Parent | Child | Cardinality and enforcement |
| --- | --- | --- |
| theatres | screens | One to many, theatre_id FK |
| screens | seats | One to many, screen_id FK |
| screens | shows | One to many, screen_id FK |
| movies | shows | One to many, movie_id FK |
| users | bookings | One to many, user_id FK |
| shows | bookings | One to many, screen/start FK |
| shows | show_seats | One to many, screen/start FK |
| seats | show_seats | One to many across shows, screen/row/number FK |
| bookings | show_seats | Zero to many current allocations, nullable composite FK |
| bookings | booking_seats | One to many historical items; a booking may temporarily have none |
| bookings | payment_events | Zero to many, booking_id FK |

booking_seats deliberately omits the booking's show coordinates. Its FK proves
the booking exists, but the transaction must validate each seat against that
booking's inventory. Cancelled bookings retain their historical items while
inventory can later belong to another booking.

## Functional dependencies and normal forms

A candidate key is minimal; a unique key containing booking_id plus other
columns is a superkey, not an additional candidate key. Atomic values establish
1NF under this assignment's display-value treatment of addresses and names.
The following analysis assumes no additional business dependencies beyond
those stated, and email/string equality follows each column's collation.

| Table | Candidate keys / determinants | Review |
| --- | --- | --- |
| theatres | theatre_id | Determines name/address; neither is assumed unique. BCNF, hence 1NF–3NF. |
| screens | screen_id; (theatre_id, screen_name) | Either determines all columns; no partial dependency. BCNF. |
| seats | seat_id; (screen_id, row_label, seat_number) | Either determines all columns; row and seat number repeat elsewhere. BCNF. |
| movies | movie_id | Determines title/duration; title need not be unique. BCNF. |
| shows | show_id; (screen_id, starts_at) | Either determines movie and price. BCNF; interval overlap is a separate scheduling rule. |
| users | user_id; email | Either determines all columns. BCNF. |
| bookings | booking_id; booking_reference | Either determines all booking facts. No partial/transitive dependencies under stated assumptions. BCNF. |
| booking_seats | (booking_id, row_label, seat_number) | Full key determines historical purchase_price. Item prices can differ within a booking, e.g. discounts; BCNF. |
| payment_events | payment_event_id; (provider, provider_event_id) | Either determines event facts. Processing state does not determine a timestamp value. BCNF. |
| show_seats | (screen_id, starts_at, row_label, seat_number) | Full key determines status/owner. Allocated rows also have booking_id → screen_id, starts_at, although booking_id is not unique. Intentional BCNF exception. |

For allocated inventory considered as a separate relation, another candidate
key is (booking_id, row_label, seat_number). The dependency from booking_id to
screen/start has prime attributes on its right-hand side; it violates BCNF
but does not by itself violate 3NF. The actual SQL table also includes NULL
owners for available inventory, so classical NULL-free normal-form analysis
cannot simply be applied to that whole table without stating this distinction.
Do not claim every table is strictly BCNF. A stricter decomposition could
separate show inventory from current allocations and derive each allocation's
show through bookings, but same-show integrity would then need a redesigned
constraint or transaction scheme. That would be a schema migration, not a
documentation correction, and is not made in this review.

## Enforcement boundaries

Constraints cover references, seat/screen and booking/show consistency for
inventory, unique provider events, and the documented CHECK conditions.
They do not enforce all-or-none seat acquisition, item-total equality, booking
status versus inventory status, expiry cleanup, show overlap, or refund delivery.
Those require transactions or an application worker. The test procedures are
executable examples; they are not installed production booking APIs.

The nine constraint checks, six lifecycle checks, two-client lock exclusion,
P2 filter cases, and fresh-schema replay have user-provided execution evidence.
The new committed-winner/partial-claim test is prepared but not yet executed.
Concurrent expiry-versus-confirmation, deadlock retries, and an actual external
payment integration are not verified by these examples.
