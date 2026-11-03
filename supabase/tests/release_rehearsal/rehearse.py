"""Runs the real publisher against a replay of production's schema, through a real
PostgREST. Only object storage is faked. Every URL is loopback: nothing here can reach
production. Argument: path to the signed-release migration."""
import base64, hashlib, hmac, http.client, json, os, subprocess, sys, tempfile, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
P = os.environ["PIPELINE_REPO"] + "/scripts"
sys.path[:0] = [P, P + "/tests", str(Path(__file__).parent)]
SECRET = "disposable-fixture-only-secret-0123456789abcdef"
NAME, PG_PORT, REST_PORT, PROXY_PORT = "pg-a2-rehearsal", 55433, 55434, 55435

def jwt(role):
    enc = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
    head = enc(b'{"alg":"HS256","typ":"JWT"}')
    body = enc(json.dumps({"role": role, "exp": int(time.time()) + 7200}).encode())
    sig = enc(hmac.new(SECRET.encode(), f"{head}.{body}".encode(), hashlib.sha256).digest())
    return f"{head}.{body}.{sig}"
SERVICE, ANON = jwt("service_role"), jwt("anon")
os.environ.update(SUPABASE_URL=f"http://127.0.0.1:{PROXY_PORT}", SUPABASE_SERVICE_ROLE_KEY=SERVICE)

def psql(sql, user="postgres"):
    r = subprocess.run(["docker", "exec", "-i", NAME, "psql", "-X", "-U", user, "-d", "postgres",
                        "-v", "ON_ERROR_STOP=1", "-Atq"], input=sql, text=True, capture_output=True)
    if r.returncode:
        raise RuntimeError(r.stderr)
    return r.stdout.strip()

class Proxy(BaseHTTPRequestHandler):
    """Supabase serves PostgREST under /rest/v1; PostgREST itself has no prefix."""
    def log_message(self, *a): pass
    def _go(self):
        if not self.path.startswith("/rest/v1"):
            self.send_response(503); self.send_header("Content-Length", "0"); self.end_headers(); return
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        c = http.client.HTTPConnection("127.0.0.1", REST_PORT, timeout=60)
        hdrs = {k: v for k, v in self.headers.items() if k.lower() not in ("host", "content-length", "apikey", "accept-encoding", "connection")}
        try:
            c.request(self.command, self.path[len("/rest/v1"):] or "/", body, hdrs)
            r = c.getresponse(); data = r.read()
        except Exception:
            self.send_response(503); self.send_header("Content-Length", "0"); self.end_headers(); return
        self.send_response(r.status)
        for k, v in r.getheaders():
            if k.lower() not in ("transfer-encoding", "content-length", "connection"):
                self.send_header(k, v)
        self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
    do_GET = do_POST = do_PATCH = do_DELETE = do_HEAD = _go
ThreadingHTTPServer.daemon_threads = True
threading.Thread(target=ThreadingHTTPServer(("127.0.0.1", PROXY_PORT), Proxy).serve_forever, daemon=True).start()

results = []
def check(name, ok, detail=""):
    results.append((name, bool(ok)))
    print(("PASS " if ok else "FAIL ") + name + (f"  [{detail}]" if detail else ""), flush=True)

def current():
    return json.loads(psql("SELECT to_jsonb(m) FROM public.export_manifest m WHERE is_current"))
def rows():
    return int(psql("SELECT count(*) FROM public.export_manifest"))
def registry(v):
    return psql(f"SELECT state FROM public.catalog_releases WHERE db_version='{v}'")
def anon_get(query):
    c = http.client.HTTPConnection("127.0.0.1", PROXY_PORT, timeout=30)
    c.request("GET", "/rest/v1/export_manifest?" + query, headers={"Authorization": "Bearer " + ANON})
    r = c.getresponse(); return r.status, json.loads(r.read() or b"null")

import release_manifest as rm, supabase_client
def rest_ready():
    for _ in range(120):
        try:
            c = http.client.HTTPConnection("127.0.0.1", REST_PORT, timeout=2); c.request("GET", "/export_manifest?limit=0", headers={"Authorization": "Bearer " + ANON})
            if c.getresponse().status == 200: return True
        except OSError: pass
        time.sleep(0.5)
    return False
assert rest_ready()
supabase_client.require_publication_contract(signed_release=False)
check("before the migration, an unsigned publisher's contract check passes on PostgREST 14.5", True)
why = None
try: supabase_client.require_publication_contract(signed_release=True)
except ValueError as e: why = str(e)
check("before the migration, a signed publish is refused by the contract check", why, why)
# ---- the migration, on rows like production's ----------------------------------------
before = {r.split("|")[0]: r for r in psql("SELECT db_version||'|'||checksum||'|'||is_current FROM public.export_manifest").splitlines()}
migration = Path(sys.argv[1]).read_text()
subprocess.run(["docker", "exec", "-i", NAME, "psql", "-X", "-U", "postgres", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-q"], input=migration, text=True, check=True, capture_output=True)
after = {r.split("|")[0]: r for r in psql("SELECT db_version||'|'||checksum||'|'||is_current FROM public.export_manifest").splitlines()}
check("migration applies to production's rows and leaves them unchanged", before == after and len(after) == 4)
check("existing rows have no sequence", psql("SELECT count(*) FROM public.export_manifest WHERE release_sequence IS NOT NULL") == "0")
check("one publish RPC, no overload", psql("SELECT count(*) FROM pg_proc WHERE proname='rotate_manifest_with_submission_approvals'") == "1")
priv = psql("SELECT has_function_privilege('anon',p.oid,'EXECUTE')||'|'||has_function_privilege('authenticated',p.oid,'EXECUTE')||'|'||has_function_privilege('service_role',p.oid,'EXECUTE') FROM pg_proc p WHERE proname='rotate_manifest_with_submission_approvals'")
check("only service_role can publish", priv == "false|false|true", priv)

import sync_to_supabase as sync, test_release_manifest as t
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
work = Path(tempfile.mkdtemp(prefix="rehearsal"))
import fakes
objects, uploads = fakes.install(work)
rm.GATE_PATH.write_text('{"a9_review_complete": false}')
rm.TRUST_PATH.write_text(json.dumps({"production_project_ref": "omayamxacvacrnvdvzhr", "test_hosts": ["127.0.0.1"], "production_keys": {}, "test_keys": {}}))
key = Ed25519PrivateKey.generate()

fail_upload = {"path": None}
fake_upload = supabase_client.upload_file
def upload(c, b, path, local, **kw):
    if fail_upload["path"] and path.startswith(fail_upload["path"]):
        raise RuntimeError("simulated: publisher died during upload")
    return fake_upload(c, b, path, local, **kw)
supabase_client.upload_file = upload
real_promote = sync._promote_registry_release

def publish(catalog, rules=None, sequence=None, **over):
    d = work / f"sig-{time.monotonic_ns()}"; d.mkdir()
    kwargs = {}
    if sequence is not None:
        text = t._build(catalog, rules, sequence=sequence, **over)
        (d / "r.json").write_bytes(text.encode()); (d / "r.sig").write_text(rm.sign_release(text, key))
        kwargs = dict(release_manifest=str(d / "r.json"), release_signature=str(d / "r.sig"), rules_dir=str(rules) if rules else None, test_project=True)
    stdout, sys.stdout = sys.stdout, open(os.devnull, "w")
    try:
        return sync.sync(str(catalog), max_workers=1, **kwargs)
    finally:
        sys.stdout.close(); sys.stdout = stdout
def refused(fn):
    try: fn()
    except Exception as e: return f"{type(e).__name__}: {str(e)[:150]}"
    return None

# ---- unsigned, as public builds run today ----------------------------------------------
picked_up = None
for _ in range(20):
    try:
        supabase_client.require_publication_contract(signed_release=True); picked_up = True; break
    except ValueError as e:
        picked_up = None; time.sleep(0.5)
check("a running PostgREST picks up the new arguments after the migration, with no restart", picked_up)
if not picked_up:
    print("(reloading schema by hand to continue)"); psql("NOTIFY pgrst, 'reload schema'"); time.sleep(3)
    supabase_client.require_publication_contract(signed_release=True)
s, b = anon_get("select=db_version&is_current=eq.true")
check("a build from before this migration reads the manifest as before", s == 200 and b == [{"db_version": "2026.10.22.012241"}], str(b))
v1 = "2026.11.03.100000"; c1 = t._make_catalog(work / "c1", version=v1)
r = publish(c1)
cur = current()
check("unsigned publish still works after the migration", r["status"] == "synced" and cur["db_version"] == v1 and cur["release_sequence"] is None, r["status"])
check("registry promoted the unsigned release", registry(v1) == "ACTIVE" and registry("2026.10.22.012241") == "RETIRED")

# ---- signed, then rules only reusing the catalog version --------------------------------
rm.TRUST_PATH.write_text(json.dumps({"production_project_ref": "omayamxacvacrnvdvzhr", "test_hosts": ["127.0.0.1"], "production_keys": {}, "test_keys": {t.KEY_ID: t._public_hex(key)}}))
v2 = "2026.11.03.110000"; c2 = t._make_catalog(work / "c2", version=v2)
publish(c2, sequence=1)
cur = current()
check("signed release publishes", cur["db_version"] == v2 and cur["release_sequence"] == 1 and cur["signed_release"] and cur["release_signature"])
s, b = anon_get("select=db_version,checksum,release_sequence,signed_release,release_signature&is_current=eq.true")
check("the anon key reads the signed columns, as a keyed build will", s == 200 and b[0]["release_sequence"] == 1 and b[0]["signed_release"] == cur["signed_release"])
rm.verify_release(b[0]["signed_release"], b[0]["release_signature"], key.public_key())
check("what anon read verifies against the key", True)

n = rows(); rules = t._make_rules(work / "rules"); uploads.clear()
result = publish(c2, rules, sequence=2)
cur = current()
check("rules-only release reuses the catalog version through the real triggers", result["status"] == "synced" and cur["db_version"] == v2 and cur["release_sequence"] == 2, result["status"])
check("rules-only release adds no manifest row", rows() == n, f"{n} -> {rows()}")
check("rules-only release uploads the rules and not the catalog", any(p.startswith("rules/") for p in uploads) and not any(p.endswith("pharmaguide_core.db") for p in uploads), ",".join(uploads)[:90])
check("registry stays ACTIVE through a rules-only release", registry(v2) == "ACTIVE")
s, b = anon_get("select=db_version&is_current=eq.true")
check("a keyless build sees no new catalog from a rules-only release", b == [{"db_version": v2}])

# ---- replay and same-sequence --------------------------------------------------------
before = current()
why = refused(lambda: publish(c2, sequence=1))
check("an older sequence is refused", why and current() == before, why)
why = refused(lambda: publish(c2, sequence=2))
check("the same sequence with different content is refused", why and current() == before, why)
result = publish(c2, rules, sequence=2)
check("re-running the same signed release changes nothing", current() == before and result["status"] == "up_to_date", result["status"])
try:
    psql(f"""SELECT public.rotate_manifest_with_submission_approvals('{v2}','3','4','2.5.0',2,'{before['checksum']}',now(),'1.0.0','[]',2,'x','y')""", user="postgres")
    direct = None
except RuntimeError as e:
    direct = str(e).splitlines()[0][:120]
check("the RPC itself refuses a replayed sequence, without the publisher", direct and current() == before, direct)

# ---- interrupted publication ---------------------------------------------------------
v3 = "2026.11.03.120000"; c3 = t._make_catalog(work / "c3", version=v3)
before = current(); fail_upload["path"] = "v" + v3
why = refused(lambda: publish(c3, sequence=3))
fail_upload["path"] = None
check("killed during upload: current release untouched", why and current() == before, why)
publish(c3, sequence=3)
check("the same release finishes on retry after a killed upload", current()["db_version"] == v3)

def during_rpc(action):
    """Blocks the RPC on the table, runs action while it waits, and returns the publisher's error."""
    holder = subprocess.Popen(["docker", "exec", "-i", NAME, "psql", "-X", "-U", "postgres", "-d", "postgres", "-q"], stdin=subprocess.PIPE, text=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    holder.stdin.write("BEGIN; LOCK TABLE public.export_manifest IN SHARE MODE; SELECT pg_sleep(60);\n"); holder.stdin.flush()
    for _ in range(40):
        if psql("SELECT count(*) FROM pg_locks l JOIN pg_class c ON c.oid=l.relation WHERE c.relname='export_manifest' AND l.mode='ShareLock' AND l.granted") != "0": break
        time.sleep(0.25)
    out = {}
    v, cat = action["version"], action["catalog"]
    th = threading.Thread(target=lambda: out.update(error=refused(lambda: publish(cat, sequence=action["sequence"]))))
    th.start()
    for _ in range(120):
        q = psql("SELECT count(*) FROM pg_stat_activity WHERE query LIKE '%rotate_manifest_with_submission_approvals%' AND wait_event_type='Lock' AND pid<>pg_backend_pid()")
        if q != "0": break
        time.sleep(0.25)
    out["waiting"] = q != "0"
    action["kill"]()
    th.join(90)
    holder.kill()
    for _ in range(120):
        try:
            psql("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query LIKE '%pg_sleep%' AND pid<>pg_backend_pid()"); break
        except RuntimeError: time.sleep(0.5)
    return out

v4 = "2026.11.03.130000"; c4 = t._make_catalog(work / "c4", version=v4)
before = current(); n = rows()
out = during_rpc(dict(version=v4, catalog=c4, sequence=4, kill=lambda: psql("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query LIKE '%rotate_manifest_with_submission_approvals%' AND wait_event_type='Lock' AND pid<>pg_backend_pid()")))
time.sleep(1)
check("backend killed inside the publish transaction: current release untouched", out["waiting"] and out["error"] and current() == before and rows() == n, str(out)[:150])
check("exactly one current row after the kill", psql("SELECT count(*) FROM public.export_manifest WHERE is_current") == "1")
publish(c4, sequence=4)
check("the same release finishes on retry after a killed backend", current()["db_version"] == v4 and current()["release_sequence"] == 4)

v5 = "2026.11.03.140000"; c5 = t._make_catalog(work / "c5", version=v5)
before = current(); n = rows()
out = during_rpc(dict(version=v5, catalog=c5, sequence=5, kill=lambda: subprocess.run(["docker", "restart", "-t", "0", NAME], capture_output=True)))
for _ in range(120):
    try:
        if psql("SELECT 1") == "1": break
    except RuntimeError: pass
    time.sleep(0.5)
for _ in range(120):
    try:
        if anon_get("select=db_version&is_current=eq.true")[0] == 200: break
    except Exception: pass
    time.sleep(0.5)
check("Postgres crashed inside the publish transaction: current release untouched", out["waiting"] and out["error"] and current() == before and rows() == n, str(out)[:150])
publish(c5, sequence=5)
check("the same release finishes on retry after the crash", current()["db_version"] == v5)

v6 = "2026.11.03.150000"; c6 = t._make_catalog(work / "c6", version=v6)
def dies(*a, **k): raise RuntimeError("simulated: publisher died after the flip")
sync._promote_registry_release = dies
why = refused(lambda: publish(c6, sequence=6))
sync._promote_registry_release = real_promote
check("publisher died after the flip: the new release is current, registry VALIDATING", why and current()["db_version"] == v6 and registry(v6) == "VALIDATING", registry(v6))
result = publish(c6, sequence=6)
check("re-running after that finishes the registry and rotates nothing", result["status"] == "up_to_date" and registry(v6) == "ACTIVE" and current()["release_sequence"] == 6, result["status"])

# ---- rollback -------------------------------------------------------------------------
v7 = "2026.11.03.160000"; c7 = t._make_catalog(work / "c7", version=v7)
publish(c7, sequence=7, block_catalog=[v6], block_rules=["1.0.14"])
cur = current()
s, b = anon_get("select=db_version&is_current=eq.true")
check("rollback under a fresh version and newer sequence publishes", cur["db_version"] == v7 and cur["release_sequence"] == 7 and json.loads(cur["signed_release"])["blocked_versions"]["catalog"] == [v6])
check("a keyless build sees the rollback as a newer db_version", b == [{"db_version": v7}])
before = current()
why = refused(lambda: publish(c6, sequence=8))
check("re-using a retired catalog version is refused before anything changes", why and "RETIRED" in why.upper() and current() == before, why)
why = refused(lambda: publish(c6, sequence=6))
check("the replaced bad release can't be replayed", why and current() == before, why)


# ---- a publisher process really killed --------------------------------------------------
import signal
HERE = str(Path(__file__).parent)
def signed_kwargs(catalog, rules, sequence, **over):
    d = work / f"sig-{time.monotonic_ns()}"; d.mkdir()
    text = t._build(catalog, rules, sequence=sequence, **over)
    (d / "r.json").write_bytes(text.encode()); (d / "r.sig").write_text(rm.sign_release(text, key))
    return dict(release_manifest=str(d / "r.json"), release_signature=str(d / "r.sig"), rules_dir=str(rules) if rules else None, test_project=True)
def spawn(catalog, rules, sequence, stage, marker, **over):
    job = dict(work=str(work), catalog=str(catalog), stage=stage, marker=str(marker), kwargs=signed_kwargs(catalog, rules, sequence, **over))
    env = {**os.environ, "PYTHONPATH": ":".join([HERE, P, P + "/tests"])}
    return subprocess.Popen([sys.executable, HERE + "/fakes.py", json.dumps(job)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
def kill_at(stage, catalog, rules, sequence, **over):
    marker = work / f"m{time.monotonic_ns()}"
    child = spawn(catalog, rules, sequence, stage, marker, **over)
    for _ in range(600):
        if marker.exists() or child.poll() is not None: break
        time.sleep(0.1)
    assert marker.exists(), f"child never reached {stage}: {child.stderr.read()[-500:] if child.poll() is not None else 'still running'}"
    if stage == "rpc":
        for _ in range(40):
            if psql("SELECT count(*) FROM pg_stat_activity WHERE query LIKE '%rotate_manifest_with_submission_approvals%' AND wait_event_type='Lock' AND pid<>pg_backend_pid()") != "0": break
            time.sleep(0.1)
    child.send_signal(signal.SIGKILL); child.wait()
    assert child.returncode == -signal.SIGKILL
    return True

v8 = "2026.11.04.100000"; c8 = t._make_catalog(work / "c8", version=v8)
before = current(); n = rows()
kill_at("upload", c8, None, 8)
check("publisher SIGKILLed while uploading the catalog: current release untouched", current() == before and rows() == n)
publish(c8, sequence=8)
check("the same release finishes after that real process death", current()["db_version"] == v8 and registry(v8) == "ACTIVE")

v9 = "2026.11.04.110000"; c9 = t._make_catalog(work / "c9", version=v9)
kill_at("promote", c9, None, 9)
check("publisher SIGKILLed between the flip and promotion: new release current, registry VALIDATING", current()["db_version"] == v9 and registry(v9) == "VALIDATING", registry(v9))
result = publish(c9, sequence=9)
check("a new process finishes the registry and rotates nothing", result["status"] == "up_to_date" and registry(v9) == "ACTIVE", result["status"])

v10 = "2026.11.04.120000"; c10 = t._make_catalog(work / "c10", version=v10)
holder = subprocess.Popen(["docker", "exec", "-i", NAME, "psql", "-X", "-U", "postgres", "-d", "postgres", "-q"], stdin=subprocess.PIPE, text=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
holder.stdin.write("BEGIN; LOCK TABLE public.export_manifest IN SHARE MODE; SELECT pg_sleep(60);\n"); holder.stdin.flush()
for _ in range(40):
    if psql("SELECT count(*) FROM pg_locks l JOIN pg_class c ON c.oid=l.relation WHERE c.relname='export_manifest' AND l.mode='ShareLock' AND l.granted") != "0": break
    time.sleep(0.25)
before = current()
kill_at("rpc", c10, None, 10)
holder.kill(); psql("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query LIKE '%pg_sleep%' AND pid<>pg_backend_pid()")
time.sleep(10)  # whatever PostgREST does with the orphaned call has finished by now
after = current()
check("publisher SIGKILLed during the publish call: all or nothing, one current row", after["db_version"] in (before["db_version"], v10) and psql("SELECT count(*) FROM public.export_manifest WHERE is_current") == "1", f"current={after['db_version']} registry={registry(v10)}")
publish(c10, sequence=10)
check("re-running from a new process converges", current()["db_version"] == v10 and current()["release_sequence"] == 10 and registry(v10) == "ACTIVE")

# ---- two publishers at once --------------------------------------------------------------
va, vb = "2026.11.04.130000", "2026.11.04.130001"
ca, cb = t._make_catalog(work / "ca", version=va), t._make_catalog(work / "cb", version=vb)
kids = [spawn(ca, None, 11, "none", work / "x1"), spawn(cb, None, 11, "none", work / "x2")]
for k in kids: k.wait(180)
codes = [k.returncode for k in kids]
cur = current()
check("two publishers race for one sequence: one wins, the other is refused", sorted(codes) == [0, 1] and cur["db_version"] == (va if codes[0] == 0 else vb) and cur["release_sequence"] == 11, str(codes))
check("one current row and one ACTIVE release after the race", psql("SELECT count(*) FROM public.export_manifest WHERE is_current") == "1" and psql("SELECT count(*) FROM public.catalog_releases WHERE state='ACTIVE'") == "1", psql("SELECT db_version||'='||state FROM public.catalog_releases WHERE db_version IN ('%s','%s')" % (va, vb)).replace("\n", " "))
winner = ca if codes[0] == 0 else cb

# ---- bad rules, then rolled back, on the same catalog -------------------------------------
bad = t._make_rules(work / "rules-bad", version="1.0.16", content=b"bad-rules-bytes")
publish(winner, bad, sequence=12)
s, b = anon_get("select=signed_release&is_current=eq.true")
check("a bad rules release is what a keyed build would see", json.loads(b[0]["signed_release"])["rules"]["version"] == "1.0.16")
n = rows(); before = current()
kill_at("upload", winner, t._make_rules(work / "rules-next", version="1.0.17", content=b"next"), 13)
check("publisher SIGKILLed while uploading rules: current release untouched", current() == before and rows() == n)
good = t._make_rules(work / "rules-good", version="1.0.15", content=b"rules-file-bytes")
publish(winner, good, sequence=14, block_rules=["1.0.16"])
s, b = anon_get("select=db_version,signed_release,release_signature&is_current=eq.true")
rel = json.loads(b[0]["signed_release"])
rm.verify_release(b[0]["signed_release"], b[0]["release_signature"], key.public_key())
check("a rules rollback names the older rules, blocks the bad ones and keeps the catalog", rel["rules"]["version"] == "1.0.15" and rel["blocked_versions"]["rules"] == ["1.0.16"] and rel["release_sequence"] == 14 and b[0]["db_version"] == current()["db_version"] and rows() == n)
rules_paths = [p for p in objects if p.startswith("rules/") and "1.0.15" in p]
check("the rules a phone would fetch match the signed hash", rules_paths and any(hashlib.sha256(objects[p]).hexdigest() == rel["rules"]["sha256"] for p in rules_paths), ",".join(rules_paths)[:80])

# ---- the runbook's catalog rollback, with the real command ------------------------------
bad_version = current()["db_version"]; fresh = "2026.11.05.100000"; out = work / "rollback"
env = {**os.environ}
proc = subprocess.run([sys.executable, P + "/release_manifest.py", "prepare-rollback", "--source-dir", str(c5), "--output-dir", str(out), "--db-version", fresh, "--newer-than", bad_version], capture_output=True, text=True, env=env)
check("prepare-rollback stamps the known-good build", proc.returncode == 0, (proc.stdout + proc.stderr).strip()[-120:])
publish(out, sequence=15, block_catalog=[bad_version])
cur = current()
check("the rollback publishes with the bad version blocked", cur["db_version"] == fresh and json.loads(cur["signed_release"])["blocked_versions"]["catalog"] == [bad_version] and registry(fresh) == "ACTIVE" and registry(bad_version) == "RETIRED")
data = objects.get(f"v{fresh}/pharmaguide_core.db")
check("the catalog a phone would fetch matches the manifest's hash", data and "sha256:" + hashlib.sha256(data).hexdigest() == cur["checksum"])
import sqlite3
dbf = work / "fetched.db"; dbf.write_bytes(data)
embedded = sqlite3.connect(dbf).execute("SELECT value FROM export_manifest WHERE key='db_version'").fetchone()[0]
check("and its embedded version is the fresh one, so a keyless build accepts it", embedded == fresh, embedded)
s, b = anon_get("select=db_version&is_current=eq.true")
check("a keyless build moves to the rollback by db_version alone", b == [{"db_version": fresh}])
check("every row in history kept, exactly one current", psql("SELECT count(*) FROM public.export_manifest WHERE is_current") == "1" and rows() >= 13, f"rows={rows()}")

print(f"\n{sum(ok for _, ok in results)}/{len(results)} checks passed")
sys.exit(0 if all(ok for _, ok in results) else 1)
