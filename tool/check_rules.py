"""Checks the security rules against the local emulators: each line is an
action a role should or should not be allowed to take. Run after
tool/seed_emulator.py. Talks to localhost only."""
import json
import urllib.error
import urllib.request

PROJECT = "billiard-manage"
AUTH = "http://localhost:9099/identitytoolkit.googleapis.com/v1"
FS = f"http://localhost:8080/v1/projects/{PROJECT}/databases/(default)/documents"
RTDB = "http://localhost:9000"
NS = "billiard-manage-default-rtdb"
V = "venues/test-venue"


def call(url, body=None, method="GET", token=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(urllib.request.Request(
                url, data=data, method=method, headers=headers)) as res:
            return res.status, json.load(res)
    except urllib.error.HTTPError as e:
        return e.code, None


def login(email, password):
    _, res = call(f"{AUTH}/accounts:signInWithPassword?key=fake",
                  {"email": email, "password": password, "returnSecureToken": True}, "POST")
    return res["idToken"], res["localId"]


def value(v):
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, (int, float)):
        return {"doubleValue": float(v)}
    if v is None:
        return {"nullValue": None}
    return {"stringValue": v}


def write(path, data, token, mask=True):
    q = "&".join(f"updateMask.fieldPaths={k}" for k in data) if mask else ""
    return call(f"{FS}/{path}?{q}", {"fields": {k: value(v) for k, v in data.items()}},
                "PATCH", token)[0]


def read(path, token):
    return call(f"{FS}/{path}", token=token)[0]


results = []


def check(name, status, allowed):
    ok = (status == 200) == allowed
    results.append(ok)
    print(f"{'PASS' if ok else 'FAIL'}  {'allow' if allowed else 'deny '}  {name}  (HTTP {status})")


admin, admin_uid = login("admin@test.local", "test-admin-4821")
worker, worker_uid = login("worker@test.local", "test-worker-7359")


def session(owner_uid, status="active", table="table-2"):
    return {"tableId": table, "tableName": "Stol 2", "status": status,
            "openedBy": owner_uid, "discount": 0, "hourlyRate": 40000, "venueId": "test-venue"}


def entry(uid, kind, session_id=None):
    return {"customerId": "c1", "customerName": "Ali", "type": kind, "amount": 5000,
            "sessionId": session_id, "createdBy": uid}


check("signed-out user reads tables", read(f"{V}/tables/table-1", None), False)
check("worker reads own venue's tables", read(f"{V}/tables/table-1", worker), True)
check("worker reads another venue", read("venues/other/tables/t", worker), False)

check("worker opens a session", write(f"{V}/sessions/w1", session(worker_uid), worker, mask=False), True)
check("worker opens a session in someone else's name",
      write(f"{V}/sessions/w2", session(admin_uid), worker, mask=False), False)
check("worker adds a note to it", write(f"{V}/sessions/w1", {"notes": "x"}, worker), True)
check("worker gives a discount", write(f"{V}/sessions/w1", {"discount": 50}, worker), False)
check("worker voids a session", write(f"{V}/sessions/w1", {"status": "voided"}, worker), False)
check("admin gives a discount", write(f"{V}/sessions/w1", {"discount": 50}, admin), True)
check("worker checks the session out", write(f"{V}/sessions/w1", {"status": "completed"}, worker), True)
check("worker edits a closed session", write(f"{V}/sessions/w1", {"finalTotal": 1}, worker), False)
check("admin edits a closed session", write(f"{V}/sessions/w1", {"finalTotal": 1}, admin), False)
check("worker saves a counter sale",
      write(f"{V}/sessions/w3", session(worker_uid, "completed", ""), worker, mask=False), True)
check("worker writes a pre-completed table session",
      write(f"{V}/sessions/w4", session(worker_uid, "completed"), worker, mask=False), False)

check("worker marks a table active", write(f"{V}/tables/table-2", {"status": "active"}, worker), True)
check("worker sets a table's booked end time", write(f"{V}/tables/table-2", {"sessionEndsAt": None}, worker), True)
check("worker changes a table's price", write(f"{V}/tables/table-2", {"hourlyRate": 1}, worker), False)
check("admin changes a table's price", write(f"{V}/tables/table-2", {"hourlyRate": 40000}, admin), True)
check("worker edits the menu", write(f"{V}/menu/cola", {"price": 1}, worker), False)
check("admin edits the menu", write(f"{V}/menu/cola", {"price": 10000}, admin), True)
check("worker changes the category list", write(V, {"name": "x"}, worker), False)

check("worker records a debt payment", write(f"{V}/debtEntries/e1", entry(worker_uid, "payment"), worker, mask=False), True)
check("worker records a debt from a sale", write(f"{V}/debtEntries/e2", entry(worker_uid, "debt", "w1"), worker, mask=False), True)
check("worker adds a debt by hand", write(f"{V}/debtEntries/e3", entry(worker_uid, "debt"), worker, mask=False), False)
check("worker writes off a debt", write(f"{V}/debtEntries/e4", entry(worker_uid, "writeoff"), worker, mask=False), False)
check("admin adds a debt by hand", write(f"{V}/debtEntries/e5", entry(admin_uid, "debt"), admin, mask=False), True)
check("admin writes off a debt", write(f"{V}/debtEntries/e6", entry(admin_uid, "writeoff"), admin, mask=False), True)
check("admin edits a ledger entry", write(f"{V}/debtEntries/e5", {"amount": 1}, admin), False)

check("worker makes themselves owner", write(f"users/{worker_uid}", {"role": "owner"}, worker), False)
check("worker creates a staff profile",
      write("users/new1", {"name": "n", "role": "staff", "venueId": "test-venue"}, worker, mask=False), False)
check("admin creates a staff profile",
      write("users/new2", {"name": "n", "role": "staff", "venueId": "test-venue"}, admin, mask=False), True)
check("worker reads the admin's profile", read(f"users/{admin_uid}", worker), False)

log = {"type": "sessionTransferred", "subject": "Stol 1", "byName": "x"}
check("worker's action is logged", write(f"{V}/activity/a1", {**log, "byUid": worker_uid}, worker, mask=False), True)
check("worker logs an action in the admin's name",
      write(f"{V}/activity/a2", {**log, "byUid": admin_uid}, worker, mask=False), False)
check("worker reads the activity log", read(f"{V}/activity/a1", worker), False)
check("admin reads the activity log", read(f"{V}/activity/a1", admin), True)
check("admin edits an activity entry", write(f"{V}/activity/a1", {"subject": "y"}, admin), False)
check("admin sets the day-end hour", write(V, {"dayEndHour": 5}, admin), True)

spend = {"amount": 5000, "category": "Boshqa", "paymentMethod": "cash"}
check("worker records an expense", write(f"{V}/expenses/x1", {**spend, "createdBy": worker_uid}, worker, mask=False), True)
check("worker records an expense in the admin's name",
      write(f"{V}/expenses/x2", {**spend, "createdBy": admin_uid}, worker, mask=False), False)
check("worker edits an expense", write(f"{V}/expenses/x1", {"amount": 1}, worker), False)
check("worker deletes an expense", call(f"{FS}/{V}/expenses/x1", method="DELETE", token=worker)[0], False)
check("admin deletes an expense", call(f"{FS}/{V}/expenses/x1", method="DELETE", token=admin)[0], True)

live = f"{RTDB}/venues/test-venue/sessions/table-9.json?ns={NS}"
good = {"sessionId": "s", "startedAt": 1, "totalPausedMs": 0, "status": "active"}
check("signed-out user reads live timers", call(live)[0], False)
check("worker writes a live timer", call(live + f"&auth={worker}", good, "PUT")[0], True)
check("worker writes a malformed timer",
      call(live + f"&auth={worker}", {**good, "status": "hacked"}, "PUT")[0], False)

# ── Storage: menu photos ──
import urllib.parse
BUCKET = "billiard-manage.firebasestorage.app"
PNG = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
                    "0000000d49444154789c6360000002000001e221bc330000000049454e44ae426082")


def upload(path, token, content_type="image/png", body=PNG):
    url = (f"http://localhost:9199/v0/b/{BUCKET}/o?uploadType=media&name="
           + urllib.parse.quote(path, safe=""))
    headers = {"Content-Type": content_type}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    try:
        with urllib.request.urlopen(urllib.request.Request(
                url, data=body, method="POST", headers=headers)) as res:
            return res.status
    except urllib.error.HTTPError as e:
        return e.code


def download(path, token):
    url = (f"http://localhost:9199/v0/b/{BUCKET}/o/"
           + urllib.parse.quote(path, safe="") + "?alt=media")
    headers = {"Authorization": f"Bearer {token}"} if token else {}
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers)) as res:
            return res.status
    except urllib.error.HTTPError as e:
        return e.code


photo = "venues/test-venue/menu/cola_1"
check("admin uploads a menu photo", upload(photo, admin), True)
check("worker uploads a menu photo", upload("venues/test-venue/menu/cola_2", worker), False)
check("admin uploads a non-image file",
      upload("venues/test-venue/menu/cola_3", admin, "application/pdf"), False)
check("admin uploads a photo over 2 MB",
      upload("venues/test-venue/menu/cola_4", admin, body=PNG + b"0" * (2 * 1024 * 1024)), False)
check("admin uploads into another venue", upload("venues/other/menu/x", admin), False)
check("worker views a menu photo", download(photo, worker), True)
check("signed-out user views a menu photo", download(photo, None), False)

print(f"\n{sum(results)}/{len(results)} checks passed")
