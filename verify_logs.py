import json
import urllib.request
import urllib.error
import sys
import time

ES_URL = "http://localhost:9200"
INDEX   = "fluent-bit-logs"


def check_es():
    try:
        with urllib.request.urlopen(f"{ES_URL}/_cluster/health", timeout=5) as r:
            health = json.loads(r.read())
            print(f"Elasticsearch status: {health['status']}")
            return True
    except Exception as e:
        print(f"Cannot reach Elasticsearch: {e}")
        return False


def count_docs():
    try:
        with urllib.request.urlopen(f"{ES_URL}/{INDEX}/_count", timeout=5) as r:
            data = json.loads(r.read())
            count = data.get("count", 0)
            print(f"Documents in '{INDEX}': {count}")
            return count
    except urllib.error.HTTPError as e:
        if e.code == 404:
            print(f"Index '{INDEX}' not created")
        else:
            print(f"HTTP {e.code}: {e.reason}")
        return 0


def sample_doc():
    query = json.dumps({
        "size": 3,
        "sort": [{"@timestamp": {"order": "desc"}}]
    }).encode()
    req = urllib.request.Request(
        f"{ES_URL}/{INDEX}/_search",
        data=query,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            data = json.loads(r.read())
            hits = data["hits"]["hits"]
            print(f"\n--- Latest {len(hits)} log(s) ---")
            for h in hits:
                src = h["_source"]
                print(json.dumps(src, indent=2))
    except Exception as e:
        print(f"Could not fetch sample: {e}")


if __name__ == "__main__":
    print("======\n")

    if not check_es():
        sys.exit(1)

    # Retry up to 5 times with 5s gap to give Fluent Bit time to ship logs
    for attempt in range(1, 6):
        count = count_docs()
        if count > 0:
            sample_doc()
            print(f"\nPipeline is successful.\n{count} logs.")
            sys.exit(0)
        time.sleep(5)
