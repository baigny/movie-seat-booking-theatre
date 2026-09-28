# Project Progress Tracker

Current phase: **P1 - schema and sample data**.
Current action: **batch 7 pushed; next prepare batch 8 booking tables**.

## Overall progress

| Deliverable | Status | Evidence / remaining work |
| --- | --- | --- |
| Repository and working branch | Complete | main baseline; feature/p1-p2-sql for submission |
| Local MySQL and InnoDB | Verified | User output: MySQL 8.4.9, InnoDB DEFAULT |
| P1: table structures | In progress | 6 of 10 planned tables verified |
| P1: sample rows | In progress | 6 tables populated; show count checked, show values await P2 tests |
| P1: documentation and normalization | In progress | Documented through batch 7; final review pending |
| P1: seat holds and payment handling | Pending | Inventory, bookings, payment events, transaction examples |
| P2: theatre/date showtime query | Pending | Shows table and 10-row fixture ready; detailed output check pending |
| Constraint and concurrency verification | Pending | Positive table/data checks done; rejection and race tests pending |
| Final README and clean-database run | Pending | Reconcile documentation with tested implementation |
| GitHub pull request | Pending | Open from working branch into main |

Table counts measure table work only; they are not a percentage of the whole project.

## Table tracker

| Table | Structure | Sample rows | Verification |
| --- | --- | --- | --- |
| theatres | Created | 2 rows | Verified |
| screens | Created | 3 rows | Verified |
| movies | Created | 3 rows | Verified |
| seats | Created | 8 rows | Verified |
| shows | Created | 10 rows | Structure and row count verified; values pending |
| users | Created | 2 rows | Structure and data verified |
| show_seats | Pending | Pending | Pending |
| bookings | Pending | Pending | Pending |
| booking_seats | Pending | Pending | Pending |
| payment_events | Pending | Pending | Pending |

## Batch history

Each implementation batch adds two SQL statements, updates the README, is
verified, and is then committed and pushed. Verification SQL is separate from
the two implementation statements. Database verification so far is based on
user-supplied MySQL output; git diff checks run locally.

| Batch | Two statements | State | Pushed commit |
| --- | --- | --- | --- |
| 1 | CREATE DATABASE + USE | Verified and pushed | f5a42c3 |
| 2 | CREATE theatres + CREATE screens | Verified and pushed | 5f515eb |
| 3 | INSERT theatres + INSERT screens | Verified and pushed | 9edd412 |
| 4 | CREATE movies + CREATE seats | Verified and pushed | b362be6 |
| 5 | INSERT movies + INSERT seats | Verified and pushed | 3c2320f |
| 6 | CREATE shows + CREATE users | Verified and pushed | 1d20609 |
| 7 | INSERT shows + INSERT users | User rows and both counts verified; pushed | 1e4161e |

## Remaining sequence

1. Prepare batch 8; verify individual sample show values during P2 testing.
2. Define and populate the remaining inventory, booking, and payment tables in
   dependency order, retaining two new SQL statements per implementation commit.
3. Add executable consistency/transaction examples and document hold expiry,
   safe seat confirmation, and idempotent payment handling.
4. Implement P2 and verify theatre/date filtering and showtime ordering.
5. Run negative constraint tests, two-session booking tests, and a fresh-database
   execution of the complete scripts. Record results and any limitations.
6. Finalize README, normalization analysis, relationships, and sample output;
   open the submission PR.

## Update rule

Update this tracker and README after each step. Mark Prepared, Verified, Committed,
and Pushed based on actual evidence. Do not mark the whole P1 complete merely
because its tables exist; sample rows, documentation, and concurrency work remain.
