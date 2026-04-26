import json
import urllib.request
import urllib.error
import sys
import time

ES_URL  = "http://localhost:9200"
INDICES = ["fluent-bit-app", "fluent-bit-docker"]


def check_es():
    try:
        with urllib.request.urlopen(f"{ES_URL}/_cluster/health", timeout=5) as r:
            health = json.loads(r.read())
            print(f"[OK] Elasticsearch status: {health['status']}")
            return True
    except Exception as e:
        print(f"[FAIL] Cannot reach Elasticsearch: {e}")
        return False


def count_docs(index):
    try:
        with urllib.request.urlopen(f"{ES_URL}/{index}/_count", timeout=5) as r:
            data = json.loads(r.read())
            return data.get("count", 0)
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return 0
        raise


def sample_docs(index, n=2):
    query = json.dumps({
        "size": n,
        "sort": [{"@timestamp": {"order": "desc"}}]
    }).encode()
    req = urllib.request.Request(
        f"{ES_URL}/{index}/_search",
        data=query,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            data = json.loads(r.read())
            return [h["_source"] for h in data["hits"]["hits"]]
    except Exception:
        return []


def check_index(index, label):
    print(f"\n{'─'*55}")
    print(f"  {label}")
    print(f"  Index: {index}")
    print(f"{'─'*55}")

    for attempt in range(1, 6):
        count = count_docs(index)
        if count > 0:
            print(f"  [OK] {count} document(s) indexed.")
            docs = sample_docs(index)
            if docs:
                print(f"  Latest sample:")
                print("  " + json.dumps(docs[0], indent=4).replace("\n", "\n  "))
            return True
        print(f"  Attempt {attempt}/5 — waiting 5s...")
        time.sleep(5)

    print(f"  [FAIL] No documents found. Check: docker logs fluent-bit")
    return False


if __name__ == "__main__":
    print("=" * 55)
    print("  Fluent Bit Dual-Input Verification")
    print("=" * 55)

    if not check_es():
        sys.exit(1)

    r1 = check_index("fluent-bit-app",    "INPUT 1 — File Tail (/logs/app.log)")
    r2 = check_index("fluent-bit-docker", "INPUT 2 — Docker Socket (all containers)")

    print(f"\n{'='*55}")
    if r1 and r2:
        print("  [SUCCESS] Both inputs are working!")
        print("  Open Kibana → Discover → create data views for:")
        print("    fluent-bit-app    (structured app logs)")
        print("    fluent-bit-docker (all container logs)")
    elif r1:
        print("  [PARTIAL] File tail OK, Docker socket not yet.")
        print("  Check: docker logs fluent-bit")
    else:
        print("  [FAIL] Check: docker logs fluent-bit")
    print("=" * 55)
