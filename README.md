# Movie Seat Booking Theatre — Data Modeling

Repository: [baigny/data-modeling-movie-seat-booking-theatre](https://github.com/baigny/data-modeling-movie-seat-booking-theatre)

P1/P2 submission in preparation. See [PLAN.md](PLAN.md) for the agreed scope,
implementation steps, verification, and references.

## Submission files

- [sql/p1.sql](sql/p1.sql): schema and sample data (pending).
- [sql/p2.sql](sql/p2.sql): shows by theatre and date (pending).

## Target database

MySQL 8.0.16 or newer with InnoDB. Dates and showtimes use Indian local time
consistently for this assignment.

Execution will use local MySQL Community Server and the MySQL command-line
client; Workbench is an optional visual editor. No signed-in online database
platform, cloud subscription, or trial credits are required. Local database
login and InnoDB verification are still pending. MySQL Community Server 8.4.9
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

## Progress

- Plan and SQL placeholders created; schema implementation is pending.
- Step 1: GitHub repository created and confirmed empty before initial upload.
- Step 2: Initial setup contains the README, project plan, and SQL placeholders.
  SQL implementation will begin on `feature/p1-p2-sql` after this baseline commit.
- Incremental README updates and two-statement SQL batches agreed.
- The mysql command was not found on the current shell PATH. This does not
  establish whether MySQL Server or Workbench is installed.
- Database checks have not yet been executed against a running MySQL instance.
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
- Next, connect using your configured database credentials and run SHOW ENGINES.
- Passwords belong in your local credential storage, not in these project files.

## Reference execution workflow

[Ghanshyam's Airtribe database assignment](https://github.com/ghanshyamca/BookMyShow-database-design)
documents importing schema.sql and queries.sql through the MySQL command-line
client. Its schema explicitly uses InnoDB. We will use the same file-based
workflow with our own independently validated SQL and record actual results.

## Remaining documentation

The completed submission will include a table-by-table data dictionary,
relationships, example rows, normalization reasoning through BCNF, concurrency
transaction examples, execution instructions, and actual verification results.
