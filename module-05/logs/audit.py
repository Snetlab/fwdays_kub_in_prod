"""Write Kyverno Pod audit failures to stdout as structured logs."""
import json
import ssl
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

credentials = Path("/var/run/secrets/kubernetes.io/serviceaccount")
tls = ssl.create_default_context(cafile=str(credentials / "ca.crt"))
endpoint = "https://kubernetes.default.svc/api/v1/events"
policy = "module02-read-only-root/require-read-only-root"


def events(**parameters):
    query = urlencode({"fieldSelector": "reason=PolicyViolation", **parameters})
    token = (credentials / "token").read_text().strip()
    request = Request(f"{endpoint}?{query}", headers={"Authorization": f"Bearer {token}"})
    return urlopen(request, context=tls, timeout=75)


def run():
    version = None
    while True:
        try:
            if version is None:
                with events() as response:
                    version = json.load(response)["metadata"]["resourceVersion"]
            with events(watch="true", resourceVersion=version, timeoutSeconds=60,
                        allowWatchBookmarks="true") as response:
                for line in response:
                    record = json.loads(line)
                    event = record["object"]
                    if record["type"] == "ERROR":
                        if event.get("code") == 410:
                            version = None
                            break
                        raise RuntimeError(event.get("message", "event watch failed"))
                    version = event["metadata"]["resourceVersion"]
                    if record["type"] not in ("ADDED", "MODIFIED"):
                        continue
                    pod = event.get("involvedObject", {})
                    message = event.get("message", "")
                    if pod.get("kind") == "Pod" and f"policy {policy} fail:" in message:
                        print(json.dumps({
                            "namespace": pod["namespace"],
                            "pod": pod["name"],
                            "policy": policy,
                            "message": message,
                        }), flush=True)
        except HTTPError as error:
            if error.code == 410:
                version = None
            else:
                print(f"event watch: HTTP {error.code}", flush=True)
                time.sleep(5)
        except (URLError, TimeoutError, RuntimeError) as error:
            print(f"event watch: {error}", flush=True)
            time.sleep(5)


if __name__ == "__main__":
    run()
