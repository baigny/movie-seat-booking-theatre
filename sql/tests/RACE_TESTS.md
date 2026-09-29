# Committed winner and partial seat claim

Status: prepared, execution pending. Use two mysql clients on the same server.
The generator creates a new test schema from P1. All writes are confined to it;
it is retained for inspection, and the original project schema is unchanged.
Regenerate for a repeat run; never rerun the same setup file.

From PowerShell in the repository: `./sql/tests/prepare_race_run.ps1`.
The files generated during preparation are already ready for the first run.

1. In terminal A run:

   ```sql
   SOURCE C:/data-modelling-movie-theatre/sql/tests/race_setup.generated.sql;
   SOURCE C:/data-modelling-movie-theatre/sql/tests/race_a.generated.sql;
   ```

   Stop on any error. expected_one_claimed must be 1. A holds B1 and a payment
   event uncommitted. Keep A open.

2. In terminal B run:

   ```sql
   SOURCE C:/data-modelling-movie-theatre/sql/tests/race_b.generated.sql;
   ```

   B must wait inside CALL; it should not finish before A commits.

3. While B is waiting, in A run within 120 seconds:

   ```sql
   COMMIT;
   ```

4. B should finish with two PASS rows: committed winner retained/partial
   two-seat claim rolled back, and committed payment event retained once.
   Its final rows must show B1 sold to booking 1 and B2 available / NULL.
   Report whether B actually waited: PASS rows alone cannot prove overlap.

5. After both scripts finish, switch both clients back:

   ```sql
   USE movie_seat_booking;
   ```

A's committed claim makes B's guarded update affect zero rows for B1. B can
provisionally claim B2, but its two-seat requirement fails, so it rolls back B2.
The procedure asserts this state rather than committing a partial request.
The duplicate-payment check occurs after A commits; it verifies replay against
a committed winner, not two simultaneous webhook handlers. This probe adds a
seat to booking 1 without updating its historical items/total; it isolates lock
and uniqueness behavior in disposable test data, not full booking consistency.
No money is transferred. An error means the run is unverified; roll back both
sessions before investigating. The 120-second timeout is restored in B after
the procedure returns. Further concurrent lifecycle races remain outside this test.
