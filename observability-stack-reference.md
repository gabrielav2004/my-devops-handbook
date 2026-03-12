# Log Observability Stack Evolution

> **Author**: DevOps Engineer  
> **Date**: December 2025  
> **Purpose**: Learning reference for log observability implementation

---

## Table of Contents

1. [Overview](#overview)
2. [The Problem](#the-problem)
3. [Stack Evolution](#stack-evolution)
4. [Iteration 1: Alloy + Loki + Grafana](#iteration-1-alloy--loki--grafana)
5. [Iteration 2: OpenTelemetry Collector + Loki](#iteration-2-opentelemetry-collector--loki)
6. [Iteration 3: OpenTelemetry Collector + Parseable](#iteration-3-opentelemetry-collector--parseable-final)
7. [Alternative: Direct Application Streaming](#alternative-direct-application-streaming)
8. [Key Learnings](#key-learnings)
9. [Final Recommendation](#final-recommendation)
10. [References](#references)

---

## Overview

This document chronicles the evolution of a log observability stack from a complex Grafana Alloy + Loki + Grafana setup to a simpler OpenTelemetry Collector + Parseable solution. The journey highlights lessons about configuration complexity, tool selection, and matching observability to actual needs.

**Key Takeaway:** For small teams, simpler observability tools with familiar query languages (SQL) often beat more powerful but complex alternatives (LogQL).

---

## The Problem

**Context:**
- Deployment logs written to files (`/var/log/webhook_deploy/run_logs/*.log`)
- Need to aggregate and query logs across deployments
- Small team without dedicated observability engineers
- Want to avoid spending days on log infrastructure

**Requirements:**
- Collect logs from deployment scripts
- Query logs to debug failed deployments
- Retain logs for reasonable period (30-90 days)
- Simple to set up and maintain
- Familiar query language

**Initial Constraints:**
- Dynamic log files (`run_1.log`, `run_2.log`, etc.)
- No budget for commercial observability platforms
- Limited operational overhead capacity
- Preference for open-source solutions

---

## Stack Evolution

### Timeline

```
Week 1:   Grafana Alloy + Loki + Grafana (struggled with config)
Week 2:   OpenTelemetry Collector + Loki (worked but heavy)
Week 2-3: OpenTelemetry Collector + Parseable (final solution)
```

---

## Iteration 1: Alloy + Loki + Grafana

### Architecture

```
Log Files → Grafana Alloy → Loki → Grafana
```

### Alloy Configuration

**File: `/etc/alloy/config.alloy`**

```hcl
livedebugging {
  enabled = true
}

local.file_match "local_files" {
  targets = [
    {
      __path__ = "/var/log/webhook_deploy/run_logs/*.log",
      job      = "webhook_deploy",
      hostname = "deploy-server-01",
    }
  ]
  sync_period = "5s"
}

loki.source.file "log_scrape" {
  targets       = local.file_match.local_files.targets
  forward_to    = [loki.write.remote_loki.receiver]
  tail_from_end = false
}

loki.write "remote_loki" {
  endpoint {
    url = "http://loki:3100/loki/api/v1/push"
  }
}
```

### Loki Configuration

**File: `/etc/loki/config.yml`**

```yaml
auth_enabled: false

server:
  http_listen_port: 3100
  grpc_listen_port: 9096

common:
  instance_addr: 127.0.0.1
  path_prefix: /tmp/loki
  storage:
    filesystem:
      chunks_directory: /tmp/loki/chunks
      rules_directory: /tmp/loki/rules
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory  # Use inmemory for single instance

schema_config:
  configs:
    - from: 2020-10-24
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

limits_config:
  allow_structured_metadata: true
```

### Problems Encountered

#### 1. Configuration Syntax Errors

**Issue:** HCL syntax is strict and errors are cryptic

```hcl
# ERROR: Missing comma
{
  __path__ = "/path/to/*.log"
  job = "myapp"  # Missing comma here!
}

# CORRECT:
{
  __path__ = "/path/to/*.log",
  job      = "myapp",
}
```

#### 2. Parameter Name Confusion

Different Alloy versions use different parameter names:

```hcl
# Some versions use:
path_targets = [...]

# Others use:
targets = [...]

# Had to check documentation for specific version
```

#### 3. File Discovery Issues

Dynamic files like `run_1.log`, `run_2.log` weren't always discovered:

```hcl
# Pattern matching issues
__path__ = "/var/log/webhook_deploy/run_logs/*.log"

# sync_period sometimes too slow
sync_period = "5s"  # Files created between syncs were missed
```

#### 4. Permission Problems

```bash
# Alloy running as specific user couldn't read logs
sudo -u alloy ls -la /var/log/webhook_deploy/run_logs/
# Permission denied

# Solution: Fix permissions or run Alloy as root (not ideal)
sudo chown -R alloy:alloy /var/log/webhook_deploy/
```

#### 5. Loki Configuration Complexity

```yaml
# Wrong kvstore for single instance caused startup hangs
ring:
  kvstore:
    store: memberlist  # WRONG - for clusters only

# Correct for single instance:
ring:
  kvstore:
    store: inmemory
```

**Error encountered:**
```
level=debug msg="module waiting for initialization" module=ring waiting_for=server
level=debug msg="module waiting for initialization" module=store waiting_for=server
# Hung indefinitely...
```

#### 6. "Noop Client" Error

```
msg="failed to register collector with remote server" 
service=remotecfg 
err="noop client"
```

This was a harmless warning about remote configuration (which we weren't using), but caused confusion during debugging.

### What Worked

✅ Livedebugging UI (`http://localhost:12345`) helped visualize components  
✅ Loki's label-based querying (once working) was powerful  
✅ Grafana dashboards (once set up) looked professional  

### Rating: 5/10

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Setup Difficulty** | 3/10 | Very difficult, cryptic errors |
| **Configuration** | 4/10 | HCL syntax is finicky |
| **Documentation** | 6/10 | Exists but version-specific issues |
| **Query Language** | 7/10 | LogQL is powerful but has learning curve |
| **Resource Usage** | 6/10 | 3 containers (Alloy, Loki, Grafana) |
| **Maintenance** | 5/10 | Need to understand HCL and LogQL |

**Verdict:** Too complex for simple log aggregation needs.

---

## Iteration 2: OpenTelemetry Collector + Loki

### Architecture

```
Log Files → OTel Collector → Loki → Grafana
```

### Why Switch to OTel?

- ✅ Industry standard (CNCF project)
- ✅ Better documentation
- ✅ Larger community
- ✅ Simpler YAML configuration (no HCL)
- ✅ Vendor-neutral

### OpenTelemetry Collector Configuration

**File: `/etc/otel/config.yaml`**

```yaml
receivers:
  filelog:
    include:
      - /var/log/webhook_deploy/run_logs/*.log
    include_file_path: true
    start_at: beginning
    operators:
      - type: json_parser
        timestamp:
          parse_from: attributes.timestamp
          layout: '%Y-%m-%dT%H:%M:%S'

exporters:
  loki:
    endpoint: http://loki:3100/loki/api/v1/push
    labels:
      attributes:
        job: webhook_deploy
        host: deploy-server

processors:
  batch:
    timeout: 10s
    send_batch_size: 100

service:
  pipelines:
    logs:
      receivers: [filelog]
      processors: [batch]
      exporters: [loki]
```

### Deployment

```bash
# Docker Compose
version: '3.8'

services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    volumes:
      - ./config.yaml:/etc/otelcol/config.yaml:ro
      - /var/log/webhook_deploy:/var/log/webhook_deploy:ro
    command: ["--config=/etc/otelcol/config.yaml"]
    restart: unless-stopped

  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"
    volumes:
      - ./loki-config.yml:/etc/loki/config.yml
      - loki-data:/tmp/loki
    command: -config.file=/etc/loki/config.yml

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana

volumes:
  loki-data:
  grafana-data:
```

### Improvements Over Alloy

✅ **YAML configuration** - Familiar to most developers  
✅ **No syntax errors** - YAML is more forgiving  
✅ **Better file discovery** - Worked reliably with dynamic files  
✅ **Easier debugging** - Clear error messages  
✅ **Standard tooling** - Part of CNCF ecosystem  

### Remaining Issues

❌ **Still 3 containers** to manage (OTel, Loki, Grafana)  
❌ **LogQL learning curve** - Team had to learn query language  
❌ **Grafana complexity** - Dashboard configuration was overkill  
❌ **Resource usage** - Combined memory footprint ~800MB  

### Rating: 7/10

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Setup Difficulty** | 8/10 | Much easier than Alloy |
| **Configuration** | 9/10 | YAML is straightforward |
| **Documentation** | 9/10 | Excellent OTel docs |
| **Query Language** | 7/10 | Still LogQL (learning curve) |
| **Resource Usage** | 6/10 | Still 3 containers |
| **Maintenance** | 7/10 | Simpler but still multi-service |

**Verdict:** Better than Alloy, but still more complex than needed.

---

## Iteration 3: OpenTelemetry Collector + Parseable (Final)

### Architecture

```
Log Files → OTel Collector → Parseable (Built-in UI)
```

### Why Parseable?

**Parseable** is a lightweight, cloud-native log analytics platform:

- ✅ **Single binary** - No separate visualization layer
- ✅ **Built-in UI** - No Grafana needed
- ✅ **SQL queries** - Familiar to everyone
- ✅ **S3-compatible storage** - Standard backend
- ✅ **Lower resource footprint** - ~200MB vs 800MB
- ✅ **Simpler deployment** - One container vs three

### Parseable Deployment

**File: `run_parseable.sh`**

```bash
#!/bin/bash

docker run -d \
  --name parseable \
  -p 8000:8000 \
  -p 8001:8001 \
  -p 8002:8002 \
  -v /tmp/parseable/data:/parseable/data \
  -v /tmp/parseable/staging:/parseable/staging \
  -e P_FS_DIR=/parseable/data \
  -e P_STAGING_DIR=/parseable/staging \
  -e P_USERNAME=admin \
  -e P_PASSWORD=test_parse3515 \
  parseable/parseable:latest \
  parseable local-store
```

**Ports:**
- `8000` - HTTP API and UI
- `8001` - Internal communication
- `8002` - Query interface

### OpenTelemetry Collector Configuration

**File: `parse-otel.yaml`**

```yaml
receivers:
  filelog:
    include: [ "/var/log/app/*.log" ]
    start_at: beginning

exporters:
  otlphttp/parseablelogs:
    endpoint: 'http://<PARSEABLE_IP>:8000'
    headers:
      Authorization: 'Basic YWRtaW46dGVzdF9wYXJzZTM1MTU='  # base64(admin:test_parse3515)
      X-P-Stream: sample-app-logs
      X-P-Log-Source: otel-logs
      Content-Type: application/json
    encoding: json
    tls:
      insecure: true

processors:
  batch: null

service:
  pipelines:
    logs:
      receivers:
        - filelog
      exporters:
        - otlphttp/parseablelogs
```

### Docker Compose for OTel

**File: `docker-compose-otel.yaml`**

```yaml
services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    container_name: otel-collector
    # No ports mapped - collector only sends data outbound
    volumes:
      - ./parse-otel.yaml:/etc/otelcol/config.yaml:ro
      - ./run_logs:/var/log/app:ro  # Mount host logs
    user: "0:0"  # Run as root to read host-mounted logs
    command: ["--config=/etc/otelcol/config.yaml"]
    restart: unless-stopped
```

### Setup Steps

```bash
# 1. Generate Base64 auth header
echo -n "admin:test_parse3515" | base64
# Output: YWRtaW46dGVzdF9wYXJzZTM1MTU=

# 2. Start Parseable
chmod +x run_parseable.sh
./run_parseable.sh

# 3. Verify Parseable is running
curl http://localhost:8000/api/v1/liveness
# Response: {"status":"ok"}

# 4. Start OTel Collector
docker-compose -f docker-compose-otel.yaml up -d

# 5. Check collector logs
docker logs -f otel-collector

# 6. Access Parseable UI
# Open browser: http://localhost:8000
# Login: admin / test_parse3515
```

### Querying Logs in Parseable

Access UI at `http://localhost:8000` and run SQL queries:

```sql
-- View all recent logs
SELECT * FROM "sample-app-logs" 
ORDER BY p_timestamp DESC 
LIMIT 100;

-- Filter by content
SELECT * FROM "sample-app-logs" 
WHERE body LIKE '%ERROR%' 
ORDER BY p_timestamp DESC;

-- Filter by deployment
SELECT * FROM "sample-app-logs" 
WHERE body LIKE '%run_123%'
ORDER BY p_timestamp;

-- Count logs by time bucket
SELECT 
  DATE_TRUNC('minute', p_timestamp) as time_bucket,
  COUNT(*) as log_count
FROM "sample-app-logs"
GROUP BY time_bucket
ORDER BY time_bucket DESC
LIMIT 60;

-- Find failed deployments
SELECT * FROM "sample-app-logs"
WHERE body LIKE '%❌%' OR body LIKE '%failed%'
ORDER BY p_timestamp DESC;
```

### Production Configuration

**For production, use S3 backend:**

```bash
docker run -d \
  --name parseable \
  -p 8000:8000 \
  -e P_S3_URL=https://s3.amazonaws.com \
  -e P_S3_ACCESS_KEY=<your-key> \
  -e P_S3_SECRET_KEY=<your-secret> \
  -e P_S3_REGION=us-east-1 \
  -e P_S3_BUCKET=parseable-logs \
  -e P_USERNAME=admin \
  -e P_PASSWORD=<strong-password> \
  parseable/parseable:latest \
  parseable s3-store
```

**Enable TLS in OTel config:**

```yaml
exporters:
  otlphttp/parseablelogs:
    endpoint: 'https://parseable.yourcompany.com:8000'
    tls:
      insecure: false
      cert_file: /path/to/cert.pem
      key_file: /path/to/key.pem
```

### Comparison: Parseable vs Loki

| Feature | Loki + Grafana | Parseable |
|---------|----------------|-----------|
| **Containers** | 3 (OTel, Loki, Grafana) | 2 (OTel, Parseable) |
| **UI** | Separate Grafana | Built-in |
| **Storage** | Custom chunks | S3-compatible |
| **Query Language** | LogQL | SQL |
| **Memory Usage** | ~800MB | ~200MB |
| **Setup Time** | 2-3 hours | 30 minutes |
| **Learning Curve** | Medium (LogQL) | Low (SQL) |
| **Backup/Restore** | Complex | Standard S3 tools |

### Why This Works Better

#### 1. Single Binary
- No separate visualization layer
- Fewer containers to manage
- Simpler networking

#### 2. SQL Queries
```sql
-- Everyone knows SQL
SELECT * FROM logs WHERE body LIKE '%error%';

-- vs LogQL (need to learn)
{job="app"} |= "error"
```

#### 3. Built-in Auth
- Authentication out of the box
- No need to configure Grafana auth
- Simple username/password

#### 4. Lower Resources
```
Loki + Grafana:  ~800MB memory
Parseable:       ~200MB memory

4x reduction in resource usage
```

#### 5. S3 Backend
- Standard storage format
- Easy backups with S3 lifecycle policies
- Familiar tooling for operations

### Monitoring

```bash
# Check OTel Collector metrics
curl http://localhost:8888/metrics

# Check Parseable health
curl http://localhost:8000/api/v1/liveness

# View ingestion stats
curl -u admin:test_parse3515 \
  http://localhost:8000/api/v1/logstream/sample-app-logs/stats
```

### Rating: 8/10

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Setup Difficulty** | 9/10 | Very easy |
| **Configuration** | 9/10 | Simple YAML |
| **Documentation** | 8/10 | Good but smaller community |
| **Query Language** | 10/10 | SQL - everyone knows it |
| **Resource Usage** | 9/10 | Single container, low memory |
| **Maintenance** | 9/10 | Set and forget |

**Verdict:** Perfect for small teams needing simple log aggregation.

---

## Alternative: Direct Application Streaming

Instead of file-based collection, stream directly from application to Loki/Parseable:

### Python Loki Handler

```python
import requests
import time
import logging

class LokiHandler(logging.Handler):
    """Stream logs directly to Loki"""
    
    def __init__(self, loki_url, labels):
        super().__init__()
        self.loki_url = loki_url
        self.labels = labels
    
    def emit(self, record):
        try:
            log_entry = self.format(record)
            timestamp = str(int(time.time() * 1e9))  # nanoseconds
            
            payload = {
                "streams": [{
                    "stream": self.labels,
                    "values": [[timestamp, log_entry]]
                }]
            }
            
            requests.post(
                self.loki_url,
                json=payload,
                headers={'Content-Type': 'application/json'},
                timeout=5
            )
        except Exception as e:
            print(f"Failed to send log to Loki: {e}")

# Usage in Flask app
logger = logging.getLogger(__name__)
logger.addHandler(LokiHandler(
    loki_url="http://loki:3100/loki/api/v1/push",
    labels={"job": "webhook_deploy", "host": "server-01"}
))

logger.info("Deployment started")
```

### Pros & Cons

**Pros:**
- ✅ No file I/O overhead
- ✅ Real-time streaming
- ✅ No file discovery issues
- ✅ No log collector needed

**Cons:**
- ❌ Tight coupling to Loki
- ❌ Network dependency for logging
- ❌ Logs lost if Loki is down
- ❌ No local backup of logs

**Verdict:** Good for cloud-native apps, but keep file logging as backup.

---

## Key Learnings

### 1. Configuration Simplicity Matters

**HCL (Alloy):**
```hcl
local.file_match "files" {
  targets = [{
    __path__ = "/path/*.log",
    job = "app",
  }]
}
```

**YAML (OTel):**
```yaml
receivers:
  filelog:
    include:
      - /path/*.log
```

**Lesson:** YAML is more familiar and less error-prone for most teams.

### 2. Query Language Familiarity

**LogQL (Loki):**
```
{job="app"} |= "error" | json | level="ERROR"
```

**SQL (Parseable):**
```sql
SELECT * FROM logs 
WHERE body LIKE '%error%' 
  AND level = 'ERROR'
```

**Lesson:** SQL adoption is instant, LogQL requires learning time.

### 3. All-in-One Tools Reduce Complexity

- Loki + Grafana = 2 containers, 2 configs, 2 UIs to learn
- Parseable = 1 container, 1 config, 1 UI

**Lesson:** Fewer components = less operational overhead.

### 4. Resource Efficiency at Small Scale

For <10 deployments/day:
- Loki + Grafana is overkill
- Parseable handles volume easily with 4x less memory

**Lesson:** Match tool capabilities to actual usage patterns.

### 5. Documentation Quality vs Community Size

- OTel: Massive community, excellent docs
- Alloy: Smaller community, version-specific issues
- Parseable: Small but growing, good basics

**Lesson:** For standard tools, choose larger community. For simple tools, docs quality matters more.

### 6. Vendor Lock-in Considerations

- Alloy: Grafana-specific
- OTel: Vendor-neutral standard
- Parseable: Open-source, S3 backend portable

**Lesson:** Use standards (OTel) for collection, choose backends based on simplicity.

---

## Final Recommendation

### For Small Teams: OpenTelemetry Collector + Parseable

**Why:**
- ✅ 2 containers vs 3 (Loki + Grafana)
- ✅ SQL queries (everyone knows SQL)
- ✅ Built-in UI (no Grafana config)
- ✅ 200MB vs 800MB memory
- ✅ 30-minute setup vs 2-3 hours
- ✅ S3 backend (standard storage)

### When to Use Loki + Grafana

Use Loki + Grafana when:
- Large scale (>1000 deployments/day)
- Need advanced Grafana features (alerting, multiple data sources)
- Team already knows LogQL
- Need Grafana ecosystem integration
- Complex log correlation requirements

### Migration Path

If you grow beyond Parseable:

```
Start:  OTel → Parseable
Grow:   OTel → Loki + Grafana
Scale:  OTel → Commercial platform (DataDog, etc.)
```

**Key:** Keep OTel Collector - it's portable across backends.

### Implementation Checklist

**Day 1: Deploy Parseable**
```bash
- Run Parseable container
- Configure admin credentials
- Test UI access
```

**Day 2: Configure OTel Collector**
```bash
- Create config.yaml
- Mount log directories
- Start collector
- Verify logs flowing
```

**Day 3: Create Queries**
```sql
- Write common queries
- Save as "saved searches" in Parseable
- Share with team
```

**Week 2: Production Hardening**
```bash
- Switch to S3 backend
- Enable TLS
- Set up log retention policies
- Configure backups
```

---

## References

### Tools
- [Grafana Alloy](https://grafana.com/docs/alloy/latest/)
- [Grafana Loki](https://grafana.com/docs/loki/latest/)
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Parseable](https://www.parseable.io/docs)

### Documentation
- [OTel Collector Configuration](https://opentelemetry.io/docs/collector/configuration/)
- [Parseable API Reference](https://www.parseable.io/docs/api)
- [LogQL Documentation](https://grafana.com/docs/loki/latest/logql/)

### Community
- [OTel GitHub](https://github.com/open-telemetry/opentelemetry-collector-contrib)
- [Parseable GitHub](https://github.com/parseablehq/parseable)
- [CNCF Slack - OTel Channel](https://cloud-native.slack.com)

---

## Conclusion

The journey from Alloy to Parseable demonstrates that:

1. **Configuration simplicity matters** - YAML beat HCL
2. **Query language familiarity matters** - SQL beat LogQL
3. **All-in-one tools reduce complexity** - Built-in UI beat separate Grafana
4. **Resource efficiency matters** - 200MB beat 800MB

For small teams with straightforward log aggregation needs, **OpenTelemetry Collector + Parseable** provides the right balance of simplicity, functionality, and operational overhead.

**Final thought:** The best observability stack is the one you'll actually use and maintain, not the one with the most features.
