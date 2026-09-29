-- Template: use only through prepare_race_run.ps1's generated script.
START TRANSACTION;
UPDATE show_seats SET status = 'sold', booking_id = 1
WHERE screen_id = 1 AND starts_at = '2026-09-28 10:00:00'
  AND row_label = 'B' AND seat_number = 1
  AND status = 'available' AND booking_id IS NULL;
SELECT ROW_COUNT() AS expected_one_claimed;
INSERT INTO payment_events (provider, provider_event_id, booking_id,
    event_type, amount, processing_status, processed_at)
VALUES ('race_provider', 'race_event_001', 1, 'payment_succeeded',
    200.00, 'applied', NOW());
-- Start B now. While B is waiting, return here and execute COMMIT;
-- This is an isolated lock/uniqueness probe, not a real booking/payment workflow.
