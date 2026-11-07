"""load.py: gate 4 load. CLIENTS threads for SECONDS, each alternating a proof-1 session (background
PDF through LuaLaTeX, then OCR on the single queue) and a DOCX-to-PDF session through unoserver.
Counts completed and failed sessions so a low memory peak cannot hide a load that did not land.
    BASE=https://<fqdn> KEY=<api key> [INSECURE=1] CLIENTS=8 SECONDS=360 python test/load.py
Upload test/proof-interview.yml as proof.yml and test/load-interview.yml as load.yml first."""
import os, threading, time, warnings
import requests
warnings.filterwarnings("ignore")
BASE, KEY = os.environ["BASE"], os.environ["KEY"]
VERIFY = not os.environ.get("INSECURE")
CLIENTS, SECONDS = int(os.environ.get("CLIENTS", 8)), int(os.environ.get("SECONDS", 360))
done = {"proof": 0, "load": 0}; failed = {"proof": 0, "load": 0}; lock = threading.Lock()

def run(kind, interview, marker, limit):
    s = requests.Session(); s.verify = VERIFY; s.headers["X-API-Key"] = KEY
    try:
        n = s.get(f"{BASE}/api/session/new", params={"i": interview}, timeout=120).json()
        t0 = time.time()
        while time.time() - t0 < limit:
            q = s.get(f"{BASE}/api/session/question", params={"i": interview, "session": n["session"], "secret": n["secret"]}, timeout=300)
            if q.ok and marker in (q.json().get("subquestionText") or ""):
                with lock: done[kind] += 1
                return
            time.sleep(2)
    except Exception:
        pass
    with lock: failed[kind] += 1

def client():
    end = time.time() + SECONDS
    while time.time() < end:
        run("proof", "docassemble.playground1:proof.yml", "PDFBYTES=", 300)
        run("load", "docassemble.playground1:load.yml", "LOADDONE=", 300)

t0 = time.time()
threads = [threading.Thread(target=client) for _ in range(CLIENTS)]
for t in threads: t.start()
for t in threads: t.join()
print(f"load: {CLIENTS} clients, {time.time()-t0:.0f}s; completed proof={done['proof']} docx={done['load']}; failed proof={failed['proof']} docx={failed['load']}")
