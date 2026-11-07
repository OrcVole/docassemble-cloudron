"""Connect to docassemble's live-help monitor over websockets as the administrator, the way the
Monitor page does, and confirm the server keeps the connection (its Redis pub/sub subscription is the
path ADR 0003 patches). Prints PASS/FAIL."""
import os, re, sys, time, warnings
import requests, socketio
warnings.filterwarnings("ignore")
BASE = os.environ["BASE"]; VERIFY = not os.environ.get("INSECURE")
host = BASE.split("//", 1)[1]
s = requests.Session(); s.verify = VERIFY
p = s.get(f"{BASE}/user/sign-in"); t = re.search(r'name="csrf_token"[^>]*value="([^"]+)"', p.text).group(1)
s.post(f"{BASE}/user/sign-in", data={"csrf_token": t, "email": f"admin@{host}", "password": os.environ["ADMIN_PASSWORD"]},
       headers={"Referer": f"{BASE}/user/sign-in"})
s.get(f"{BASE}/monitor")  # the page a human operator opens; it sets up the monitor session
http = requests.Session(); http.verify = VERIFY; http.cookies.update(s.cookies)
sio = socketio.Client(http_session=http, ssl_verify=VERIFY)
events = []
sio.on("*", lambda event, *a: events.append(event), namespace="/monitor")
try:
    sio.connect(BASE, socketio_path="ws/socket.io", namespaces=["/monitor"], transports=["websocket"], wait_timeout=20)
    # The fields socketserver.update_monitor reads, as the Monitor page's JavaScript sends them.
    sio.emit("updatemonitor", {"available_for_chat": False, "subscribed_roles": {}, "phone_number": None,
                               "phone_partners_to_add": [], "phone_partners_to_terminate": []}, namespace="/monitor")
    time.sleep(6)
    held = sio.connected
    sio.disconnect()
    # The server answers updatemonitor only after its handler ran; staying connected alone proves little.
    ok = held and "updatemonitor" in events
    print(("PASS" if ok else "FAIL") + f"  live-help monitor over websockets: connected, server answered updatemonitor, held 6 s (events: {sorted(set(events)) or 'none'})")
    sys.exit(0 if ok else 1)
except Exception as e:
    print(f"FAIL  live-help monitor over websockets: {type(e).__name__}: {e}")
    sys.exit(1)
