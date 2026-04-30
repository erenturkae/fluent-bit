# Fluent Bit — Lightweight Log Pipeline for Data Engineering

> YZV 322E Applied Data Engineering
> Abdullah Eren Erentürk
> 150210327

---

## 1. What is this tool?

Fluent Bit is an open-source, lightweight log processor and forwarder maintained by the CNCF (Cloud Native Computing Foundation). It collects log data from multiple sources, applies filters and transformations, and routes the output to one or more destinations — all with a memory footprint under 1 MB. It is the production standard for log collection in Kubernetes and containerized environments.

---

## 2. Prerequisites

| Requirement | Version |
|---|---|
| OS | Linux, macOS, or Windows (WSL2) |
| Docker | 24.0 or later |
| Docker Compose | Not required (plain `docker run` used) |
| Python | 3.8 or later (for verification script) |
| curl | Any recent version |
| Free ports | 9200 (Elasticsearch), 5601 (Kibana), 24224 (Fluent Bit forward) |

> **WSL2 + Docker Desktop users:** this setup uses the Fluentd forward protocol instead of filesystem-based Docker log collection, which does not work on WSL2. No extra configuration is needed — the pipeline handles this automatically.

---

## 3. Installation

Clone the repository:

```bash
git clone https://github.com/erenturkae/fluent-bit
cd fluent-bit
```

No pip installs or build steps are required. All components run as Docker containers. The only Python dependency is the standard library (used in `verify_logs.py`).

Verify Docker is running:

```bash
docker info
```

---

## 4. Running the Example

**Start the full pipeline:**

```bash
bash run.sh start
```

This command will:
- Create a Docker network and volume
- Start Elasticsearch on port 9200
- Start Kibana on port 5601
- Start Fluent Bit with two inputs configured
- Start two log generator containers

**Verify both inputs are working:**

```bash
python verify_logs.py
```

**Other commands:**

```bash
bash run.sh status   # show container health
bash run.sh logs     # tail Fluent Bit output live
bash run.sh stop     # stop all containers
bash run.sh reset    # full cleanup (removes volume and network)
```

---

## 5. Expected Output

After running `python verify_logs.py` you should see:

```
=======================================================
  Fluent Bit Dual-Input Verification
=======================================================
[OK] Elasticsearch status: yellow

───────────────────────────────────────────────────────
  INPUT 1 — File Tail (/logs/app.log)
  Index: fluent-bit-app
───────────────────────────────────────────────────────
  [OK] 5 document(s) indexed.
  Latest sample:
  {
      "@timestamp": "2026-04-26T06:52:03.000Z",
      "level": "INFO",
      "message": "OK",
      "latency_ms": 295,
      "service": "app",
      "source": "file",
      "env": "production",
      "pipeline": "fluent-bit"
  }

───────────────────────────────────────────────────────
  INPUT 2 — Docker log files
  Index: fluent-bit-docker
───────────────────────────────────────────────────────
  [OK] 10 document(s) indexed.
  Latest sample:
  {
      "@timestamp": "2026-04-26T06:52:08.000Z",
      "service": "api",
      "level": "ERROR",
      "message": "stdout failure",
      "latency_ms": 303,
      "container_id": "1eca962f...",
      "container_name": "/log-generator-stdout",
      "source": "docker",
      "env": "production",
      "pipeline": "fluent-bit"
  }

=======================================================
  [SUCCESS] Both inputs are working!
=======================================================
```

**Kibana** is available at `http://localhost:5601`. Create data views for `fluent-bit-app` and `fluent-bit-docker` (both with `@timestamp` as the time field) to explore and visualize the logs.

---

## 6. Pipeline Architecture

```
┌─────────────────────┐     ┌─────────────────────┐
│   log-generator     │     │  log-generator-stdout│
│  (writes to volume) │     │  (fluentd log driver)│
└────────┬────────────┘     └──────────┬──────────┘
         │ /logs/app.log               │ :24224
         ▼                             ▼
┌─────────────────────────────────────────────────┐
│                  Fluent Bit                      │
│                                                  │
│  INPUT: tail          INPUT: forward             │
│  FILTER: json parse   FILTER: json parse         │
│  FILTER: enrich       FILTER: enrich             │
│         │                     │                  │
│         ▼                     ▼                  │
│   fluent-bit-app       fluent-bit-docker         │
└─────────────────────────────────────────────────┘
         │                     │
         ▼                     ▼
┌─────────────────────────────────────────────────┐
│              Elasticsearch :9200                 │
└─────────────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────────────┐
│                 Kibana :5601                     │
└─────────────────────────────────────────────────┘
```

---

## 7. Repository Structure

```
fluent-bit-demo/
├── run.sh            # pipeline orchestration script
├── fluent-bit.conf   # Fluent Bit pipeline configuration
├── parsers.conf      # JSON and Docker log parsers
├── verify_logs.py    # verification script (stdlib only)
└── README.md
```

---

## 8. AI Usage Disclosure

Claude (Anthropic) was used during this project for:
- Diagnosing why filesystem-based Docker log collection fails on WSL2 + Docker Desktop
- Identifying the correct approach (Fluentd forward protocol via `--log-driver=fluentd`)
- Debugging the Fluent Bit parser filter ordering issue that caused the `log` field to remain unparsed
- Drafting this README

All configuration files, scripts, and the final working pipeline were reviewed, tested, and verified by the student. The AI-generated suggestions were not used unreviewed — each change was applied, tested, and confirmed against actual output before being committed.

---

## References

- [Fluent Bit Official Documentation](https://docs.fluentbit.io/manual)
- [Fluent Bit Docker Image — Docker Hub](https://hub.docker.com/r/fluent/fluent-bit)
- [Fluent Bit Forward Input Plugin](https://docs.fluentbit.io/manual/pipeline/inputs/forward)
- [Elasticsearch 8.11 Reference](https://www.elastic.co/guide/en/elasticsearch/reference/8.11/index.html)
- [CNCF Fluent Bit Project Page](https://www.cncf.io/projects/fluent-bit/)
