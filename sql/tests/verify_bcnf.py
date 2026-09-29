"""MySQL CLI-only integration suite: new disposable schema, no pip dependencies.
Requires a local MySQL instance accessible through --login-path or test credentials.
Never drops databases. Only mutates its generated bcnf_verify_* schema.
"""
import argparse
import concurrent.futures as cf
import json
from pathlib import Path
import random
import re
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--mysql', default=r'C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe')
parser.add_argument('--port', type=int, default=13307)
parser.add_argument('--user', default='root')
parser.add_argument('--login-path')
parser.add_argument('--attempts', type=int, default=1000)
parser.add_argument('--workers', type=int, default=64)
parser.add_argument('--report', default='sql/tests/bcnf-results.json')
args = parser.parse_args()
schema = 'bcnf_verify_' + uuid.uuid4().hex
base = [args.mysql, '--no-defaults']
if args.login_path:
    base.append('--login-path=' + args.login_path)
base += ['--protocol=TCP', '--host=127.0.0.1', f'--port={args.port}',
         '--user=' + args.user, '--batch', '--raw', '--skip-column-names', '--unbuffered']
report = {'schema': schema, 'tests': [], 'attempts': args.attempts, 'workers': args.workers}
retry_errors = []

def raw(sql, timeout=60):
    return subprocess.run(base, input=sql, text=True, encoding='utf-8',
                          capture_output=True, timeout=timeout)

def query(sql, retry=False):
    for attempt in range(5):
        p = raw(f'USE {schema}; SET time_zone = "+05:30"; ' + sql)
        if p.returncode == 0:
            return p.stdout.strip()
        if retry and re.search(r'ERROR (1205|1213) ', p.stderr) and attempt < 4:
            retry_errors.append(int(re.search(r'ERROR (1205|1213) ', p.stderr).group(1)))
            time.sleep(random.uniform(.01, .04) * (2 ** attempt))
            continue
        raise RuntimeError(p.stderr.strip())

def check(name, condition, **details):
    if not condition:
        raise AssertionError(name + ': ' + str(details))
    report['tests'].append({'name': name, 'passed': True, **details})
    print('PASS:', name, flush=True)

def fail_expected(sql, marker):
    try:
        query(sql)
    except RuntimeError as e:
        assert marker in str(e), str(e)
        return
    raise AssertionError('Expected rejection: ' + marker)

def invariant():
    # No duplicated physical allocation, missing inventory, orphan/lost items,
    # inactive ownership, partial active booking, or duplicate applied success.
    return query('''SELECT
      (SELECT COUNT(*) FROM (SELECT b.screen_id,b.starts_at,a.row_label,a.seat_number
       FROM seat_allocations a JOIN bookings b USING(booking_id)
       GROUP BY b.screen_id,b.starts_at,a.row_label,a.seat_number HAVING COUNT(*)>1) d),
      (SELECT COUNT(*) FROM seat_allocations a JOIN bookings b USING(booking_id)
       LEFT JOIN show_seats s ON s.screen_id=b.screen_id AND s.starts_at=b.starts_at
       AND s.row_label=a.row_label AND s.seat_number=a.seat_number
       WHERE s.screen_id IS NULL OR b.status NOT IN ('held','confirmed')),
      (SELECT COUNT(*) FROM bookings b WHERE b.status IN ('held','confirmed') AND
        ((SELECT COUNT(*) FROM booking_seats i WHERE i.booking_id=b.booking_id)=0 OR
         (SELECT COUNT(*) FROM booking_seats i WHERE i.booking_id=b.booking_id)<>
         (SELECT COUNT(*) FROM seat_allocations a WHERE a.booking_id=b.booking_id))),
      (SELECT COUNT(*) FROM booking_seats i JOIN bookings b USING(booking_id)
       LEFT JOIN seat_allocations a ON a.booking_id=i.booking_id AND a.row_label=i.row_label
        AND a.seat_number=i.seat_number
       WHERE b.status IN ('held','confirmed') AND a.booking_id IS NULL),
      (SELECT COUNT(*) FROM (SELECT booking_id FROM payment_events
       WHERE processing_status='applied' AND event_type='payment_succeeded'
       GROUP BY booking_id HAVING COUNT(*)>1) p);''') == '0\t0\t0\t0\t0'

def new_show():
    # Future relative to server clock, unique starts permit concurrent fixtures.
    return int(query('''INSERT INTO shows(movie_id,screen_id,starts_at,ticket_price)
      SELECT 1,1,DATE_ADD(MAX(starts_at), INTERVAL 1 DAY),200 FROM shows;
      SET @sid=LAST_INSERT_ID();
      INSERT INTO show_seats SELECT screen_id,starts_at,'B',1 FROM shows WHERE show_id=@sid
      UNION ALL SELECT screen_id,starts_at,'B',2 FROM shows WHERE show_id=@sid;
      SELECT @sid;'''))

def hold(show, seats=None, ttl=900):
    seats = seats or [{'row': 'B', 'number': 1}]
    return int(query(f"CALL hold_seats(1,{show},'{uuid.uuid4()}',"
                     f"'{json.dumps(seats)}',{ttl});", retry=True).split('\t')[0])

class Gate:
    def __init__(self, sql):
        self.p = subprocess.Popen(base, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True, encoding='utf-8')
        self.p.stdin.write(f'USE {schema}; START TRANSACTION; {sql}; SELECT "READY";\n')
        self.p.stdin.flush()
        # Read marker with a bounded future so errors cannot hang the test forever.
        def read():
            for line in self.p.stdout:
                if line.strip() == 'READY': return True
            return False
        self.pool = cf.ThreadPoolExecutor(1)
        try:
            assert self.pool.submit(read).result(timeout=10)
        except Exception:
            self.p.kill()
            raise
        finally:
            self.pool.shutdown(wait=False)
    def release(self, command='COMMIT'):
        self.p.stdin.write(command + ';\n')
        self.p.stdin.flush()
        self.p.stdin.close()
        self.p.wait(timeout=10)
        assert self.p.returncode == 0, self.p.stderr.read()

def wait_for_block():
    until = time.monotonic() + 10
    while time.monotonic() < until:
        count = int(query('SELECT COUNT(*) FROM performance_schema.data_lock_waits;'))
        if count: return
        time.sleep(.02)
    raise AssertionError('Expected actual lock wait')

def main():
    report['mysql_version'] = raw('SELECT VERSION();').stdout.strip()
    p1 = (ROOT / 'sql/p1.sql').read_text(encoding='utf-8').replace('movie_seat_booking', schema)
    p1 = p1.replace('CREATE DATABASE IF NOT EXISTS', 'CREATE DATABASE')
    api = (ROOT / 'sql/booking_api.sql').read_text(encoding='utf-8').replace('movie_seat_booking', schema)
    installed = raw(p1 + '\n' + api)
    check('fresh BCNF schema and routines install', installed.returncode == 0, error=installed.stderr)
    check('sample allocations and item ownership', invariant())
    check('inventory contains only candidate-key attributes',
          query("SELECT GROUP_CONCAT(COLUMN_NAME ORDER BY ORDINAL_POSITION) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='show_seats';")
          == 'screen_id,starts_at,row_label,seat_number')
    constraint_cases = [
      ("INSERT INTO screens(theatre_id,screen_name) VALUES(0,'bad');", 'ERROR 1452'),
      ("INSERT INTO show_seats VALUES(1,'2026-09-28 10:00:00','A',1);", 'ERROR 1062'),
      ("INSERT INTO show_seats VALUES(2,'2026-09-28 11:00:00','B',1);", 'ERROR 1452'),
      ("INSERT INTO seat_allocations VALUES(0,'A',1);", 'ERROR 1452'),
      ("INSERT INTO seat_allocations VALUES(1,'A',1);", 'ERROR 1062'),
      ("UPDATE bookings SET status='held',hold_expires_at=NULL WHERE booking_id=1;", 'ERROR 3819'),
      ("UPDATE booking_seats SET purchase_price=-1 WHERE booking_id=1;", 'ERROR 3819'),
      ("INSERT INTO payment_events(provider,provider_event_id,booking_id,event_type,amount) VALUES('demo_provider','evt_demo_001',1,'payment_succeeded',400);", 'ERROR 1062'),
      ("UPDATE payment_events SET processed_at=NULL WHERE payment_event_id=1;", 'ERROR 3819')]
    for sql, marker in constraint_cases:
        fail_expected(sql, marker)
    check('nine constraint rejection cases', invariant())
    p2 = (ROOT / 'sql/p2.sql').read_text().replace('movie_seat_booking', schema)
    p2out = raw(p2)
    check('P2 unchanged default output', p2out.returncode == 0 and len(p2out.stdout.strip().splitlines()) == 3)
    select_only = p2[p2.index('SELECT m.title'):]
    for theatre, day, expected in [
        (2, '2026-09-28', 'Ocean of Dreams\tScreen 1\t2026-09-28\t10:00:00'),
        (1, '2026-09-29', 'The Last Train\tScreen 1\t2026-09-29\t10:00:00'),
        (1, '2026-10-05', '')]:
        actual = query(f"SET @theatre_id={theatre}, @selected_date=DATE('{day}');" + select_only)
        assert actual == expected, (theatre, day, actual)
    check('P2 alternate theatre date and empty result', True)
    # Anchor future fixtures beyond both current clock and original sample dates.
    query("INSERT INTO shows(movie_id,screen_id,starts_at,ticket_price) VALUES(1,1,DATE_ADD(SYSDATE(),INTERVAL 30 DAY),200);")
    fail_expected("CALL hold_seats(1,1,UUID(),'[{\"row\":\"A\",\"number\":1}]',60);", 'started show')
    show = new_show()
    fail_expected(f"CALL hold_seats(1,{show},UUID(),'[{{\"row\":\"X\",\"number\":1}}]',60);", 'seat does not belong')
    fail_expected(f"CALL hold_seats(1,{show},UUID(),'[{{\"row\":\"B\",\"number\":1}},{{\"row\":\"B\",\"number\":1}}]',60);", 'duplicate')
    check('invalid seat, duplicate request, past show rejected', invariant())
    # 1,000 attempts with bounded simultaneous connections, not 1,000 open sessions.
    before = int(query('SELECT COUNT(*) FROM bookings;'))
    def contender(n):
        requested = [{'row': 'B', 'number': v} for v in ([1, 2] if n % 2 else [2, 1])]
        try: return ('held', hold(show, requested))
        except RuntimeError as e:
            if 'seat unavailable' in str(e): return ('unavailable', None)
            raise
    begin = time.monotonic()
    with cf.ThreadPoolExecutor(args.workers) as pool:
        outcomes = list(pool.map(contender, range(args.attempts)))
    elapsed = time.monotonic() - begin
    winners = [b for result, b in outcomes if result == 'held']
    check('overlapping two-seat contention', len(winners) == 1 and invariant(),
          successes=len(winners), rejected=args.attempts-len(winners), seconds=round(elapsed, 3))
    check('losing holds roll back entire bookings', int(query('SELECT COUNT(*) FROM bookings;')) == before + 1)
    # Same provider event processed in concurrent transactions on the winner.
    winner = winners[0]
    with cf.ThreadPoolExecutor(32) as pool:
        outcomes = list(pool.map(lambda _: query(f"CALL confirm_payment({winner},'test','same-event',400);", retry=True), range(100)))
    check('100 concurrent duplicate confirmations', set(outcomes) == {'applied'} and invariant())
    fail_expected(f"CALL confirm_payment({winner},'test','same-event',399);", 'payload mismatch')
    check('replayed event payload mismatch rejected', invariant())
    # Expired holds: cleanup and confirmation contend on the same booking lock.
    with cf.ThreadPoolExecutor(2) as pool:
        for n in range(30):
            sid = new_show()
            bid = hold(sid)
            expired = n % 2 == 0
            if expired:
                query(f'UPDATE bookings SET hold_expires_at=DATE_SUB(SYSDATE(),INTERVAL 1 SECOND) WHERE booking_id={bid};')
            gate = Gate(f'SELECT booking_id FROM bookings WHERE booking_id={bid} FOR UPDATE')
            try:
                confirm = pool.submit(query, f"CALL confirm_payment({bid},'race','event-{n}',200);", True)
                expire = pool.submit(query, f'CALL expire_booking({bid});', True)
                wait_for_block()
            finally: gate.release()
            got_confirm, got_expire = confirm.result(15), expire.result(15)
            expected = 'refund_required' if expired else 'applied'
            assert got_confirm == expected, (n, got_confirm)
            if expired:
                replacement = hold(sid)
                assert query(f"CALL confirm_payment({bid},'race','late-{n}',200);") == 'refund_required'
                assert query(f'SELECT COUNT(*) FROM seat_allocations WHERE booking_id={replacement};') == '1'
            assert invariant(), n
    check('30 overlapping expiry/payment races and stale replays', True, expired_cases=15, live_cases=15)
    # Clock must be evaluated after waiting, not at CALL statement start.
    sid = new_show()
    bid = hold(sid, ttl=1)
    gate = Gate(f'SELECT booking_id FROM bookings WHERE booking_id={bid} FOR UPDATE')
    with cf.ThreadPoolExecutor(1) as pool:
        pending = pool.submit(query, f"CALL confirm_payment({bid},'test','expiry-during-wait',200);", True)
        try:
            wait_for_block()
            time.sleep(1.2)
        finally: gate.release()
        check('hold expires while payment waits', pending.result(15) == 'refund_required' and invariant())
    # Force a timeout, assert no partial booking remains, then retry same request.
    sid = new_show()
    coords = query(f'SELECT screen_id,starts_at FROM shows WHERE show_id={sid};').split('\t')
    gate = Gate(f"SELECT * FROM show_seats WHERE screen_id={coords[0]} AND starts_at='{coords[1]}' AND row_label='B' AND seat_number=1 FOR UPDATE")
    ref = str(uuid.uuid4())
    request = f"CALL hold_seats(1,{sid},'{ref}','[{{\"row\":\"B\",\"number\":1}}]',900);"
    try:
        fail_expected('SET SESSION innodb_lock_wait_timeout=1; ' + request, 'ERROR 1205')
        assert query(f"SELECT COUNT(*) FROM bookings WHERE booking_reference='{ref}';") == '0'
    finally: gate.release()
    query(request, retry=True)
    check('lock timeout rolls back and full request retry succeeds', invariant())
    # Deliberately violate lock order in an adversarial admin transaction.
    # Give it more undo work so InnoDB selects the API transaction as victim.
    query('CREATE TABLE test_retry_ballast (id INT PRIMARY KEY, value INT NOT NULL);' +
          'INSERT INTO test_retry_ballast VALUES ' + ','.join(f'({i},0)' for i in range(100)) + ';')
    sid = new_show()
    coords = query(f'SELECT screen_id,starts_at FROM shows WHERE show_id={sid};').split('\t')
    predicate = f"screen_id={coords[0]} AND starts_at='{coords[1]}' AND row_label='B'"
    gate = Gate(f'UPDATE test_retry_ballast SET value=value+1; SELECT * FROM show_seats WHERE {predicate} AND seat_number=2 FOR UPDATE')
    retry_before = len(retry_errors)
    with cf.ThreadPoolExecutor(1) as pool:
        pending = pool.submit(hold, sid, [{'row': 'B', 'number': 1}, {'row': 'B', 'number': 2}])
        try:
            wait_for_block()
        finally:
            gate.release(f'SELECT * FROM show_seats WHERE {predicate} AND seat_number=1 FOR UPDATE; COMMIT')
        bid = pending.result(20)
    check('real deadlock victim retried as a whole transaction',
          1213 in retry_errors[retry_before:] and invariant(), retries=retry_errors[retry_before:])
    query('DROP TABLE test_retry_ballast;')
    # Verify migration from the committed pre-BCNF schema in another fresh schema.
    migration_schema = 'bcnf_migrate_' + uuid.uuid4().hex
    old = subprocess.run(['git','show','a2153ef:sql/p1.sql'], cwd=ROOT,
                         capture_output=True, text=True, check=True).stdout
    migration = (ROOT / 'sql/migrations/001_bcnf_allocations.sql').read_text()
    migrated = raw((old + '\n' + migration).replace('movie_seat_booking', migration_schema))
    check('existing-schema migration executes', migrated.returncode == 0, error=migrated.stderr)
    migration_check = raw(f'''USE {migration_schema};
      SELECT (SELECT COUNT(*) FROM show_seats), (SELECT COUNT(*) FROM seat_allocations),
             (SELECT COUNT(*) FROM booking_seats), (SELECT COUNT(*) FROM bookings),
             (SELECT COUNT(*) FROM payment_events);
      SELECT booking_id,row_label,seat_number FROM seat_allocations ORDER BY 1,2,3;''')
    check('migration preserves inventory allocations and history', migration_check.returncode == 0
          and migration_check.stdout.strip() == '36\t2\t2\t1\t1\n1\tA\t1\n1\tA\t2')
    migration_api = raw(api.replace(schema, migration_schema))
    check('transaction routines install after migration', migration_api.returncode == 0, error=migration_api.stderr)
    # An execute-only account cannot bypass the normalized allocation mutex.
    account = 'test_' + uuid.uuid4().hex[:16]
    privilege_setup = raw(f"CREATE USER '{account}'@'localhost'; GRANT SELECT ON {schema}.* TO '{account}'@'localhost';"
        + ''.join(f"GRANT EXECUTE ON PROCEDURE {schema}.{name} TO '{account}'@'localhost';"
                  for name in ['hold_seats','confirm_payment','expire_booking']))
    assert privilege_setup.returncode == 0, privilege_setup.stderr
    app_command = [x if not x.startswith('--user=') else '--user=' + account for x in base]
    try:
        for denied_sql in ['INSERT INTO seat_allocations VALUES(1,\'B\',2);',
                           'CALL lock_booking_inventory(1);']:
            denied = subprocess.run(app_command, input=f'USE {schema}; {denied_sql}', text=True, capture_output=True)
            assert denied.returncode != 0 and re.search(r'ERROR (1142|1370)', denied.stderr), denied.stderr
        sid = new_show()
        app_hold = subprocess.run(app_command,
            input=f"USE {schema}; CALL hold_seats(1,{sid},UUID(),'[{{\"row\":\"B\",\"number\":1}}]',900);",
            text=True, capture_output=True)
        check('restricted client can hold but cannot bypass routines', app_hold.returncode == 0 and invariant(), error=app_hold.stderr)
    finally:
        raw(f"DROP USER '{account}'@'localhost';")
    report['passed'] = True

try:
    main()
except Exception as error:
    report['passed'] = False
    report['error'] = str(error)
    raise
finally:
    Path(args.report).write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print('Report:', args.report, flush=True)
