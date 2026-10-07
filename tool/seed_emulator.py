"""Fills the local Firebase emulators with a test venue, two accounts, tables
and a menu. Only ever talks to localhost; run it after
`firebase emulators:start --only auth,firestore,database`.

Test accounts (emulator only, not real logins):
  admin   admin@test.local    test-admin-4821
  worker  worker@test.local   test-worker-7359
"""
import json
import urllib.request

PROJECT = "billiard-manage"
AUTH = "http://localhost:9099/identitytoolkit.googleapis.com/v1"
FS = f"http://localhost:8080/v1/projects/{PROJECT}/databases/(default)/documents"
VENUE = "test-venue"


def post(url, body, method="POST"):
    req = urllib.request.Request(
        url,
        data=json.dumps(body).encode(),
        method=method,
        # "owner" lets the emulator skip security rules for seeding.
        headers={"Content-Type": "application/json", "Authorization": "Bearer owner"},
    )
    with urllib.request.urlopen(req) as res:
        return json.load(res)


def value(v):
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if v is None:
        return {"nullValue": None}
    if isinstance(v, list):
        return {"arrayValue": {"values": [value(x) for x in v]}}
    return {"stringValue": v}


def put(path, data):
    post(f"{FS}/{path}", {"fields": {k: value(v) for k, v in data.items()}}, "PATCH")


def account(email, password, name, role):
    uid = post(f"{AUTH}/accounts:signUp?key=fake",
               {"email": email, "password": password, "returnSecureToken": True})["localId"]
    put(f"users/{uid}", {"name": name, "email": email, "role": role,
                         "venueId": VENUE, "isActive": True})
    return uid


account("admin@test.local", "test-admin-4821", "Test Admin", "owner")
account("worker@test.local", "test-worker-7359", "Test Worker", "staff")

put(f"venues/{VENUE}", {"name": "Test Club", "address": "", "isOpen": True})
for n in (1, 2):
    put(f"venues/{VENUE}/tables/table-{n}", {
        "name": f"Stol {n}", "zone": "Zal", "type": "billiard", "status": "open",
        "hourlyRate": 40000.0, "capacity": 4, "currentSessionId": None,
        "reservationId": None, "isActive": True})
for item_id, name, price, category in (
        ("cola", "Cola", 10000.0, "Ichimliklar"),
        ("hotdog", "Hot-dog", 25000.0, "Non-dog")):
    put(f"venues/{VENUE}/menu/{item_id}", {
        "name": name, "price": price, "category": category, "imageUrl": None,
        "isAvailable": True, "stockCount": None, "venueId": VENUE})
print("seeded")
