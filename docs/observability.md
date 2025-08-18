# Observability Documentation for Logging VM

## Table of Contents

* [Observability Documentation for Logging VM](#observability-documentation-for-logging-vm)
  * [Table of Contents](#table-of-contents)
  * [Overview](#overview)
  * [Requirements](#requirements)
    * [1. Deploy Required Exporters](#1-deploy-required-exporters)
    * [2. Secret for Authentication](#2-secret-for-authentication)
    * [3. Prometheus Scrape Config](#3-prometheus-scrape-config)
  * [Monitoring](#monitoring)
    * [Components with Metrics](#components-with-metrics)
    * [Metrics](#metrics)
  * [Dashboards](#dashboards)
    * [Dashboard Management](#dashboard-management)
    * [How to Use Dashboards in Grafana](#how-to-use-dashboards-in-grafana)
    * [Available Dashboards:](#available-dashboards)
  * [Logging](#logging)
    * [Example Log Formats](#example-log-formats)
      * [Graylog (Text Format)](#graylog-text-format)
      * [MongoDB (JSON Format)](#mongodb-json-format)
      * [OpenSearch (Text Format)](#opensearch-text-format)
  * [Tracing](#tracing)
  * [Profiler](#profiler)

---

## Overview

| Observability Part        | Integration Status                |
| ------------------------- | --------------------------------- |
| [Monitoring](#monitoring) | ✅ Supported                      |
| [Logging](#logging)       | ✅ Supported                      |
| [Tracing](#tracing)       | ⛔️ Not Supported in Graylog       |
| [Profiler](#profiler)     | ⛔️ Not Supported (License Restriction) |

---

## Requirements

To enable metrics collection from Graylog, the following resources need to be created:

### 1. Deploy Required Exporters

To collect and display metrics in Grafana, we must deploy the necessary exporters for the services we want to monitor. By default, these exporters are disabled and must be explicitly enabled in the configuration.

Here’s an example configuration that ensures all required exporters are installed:

```
node_exporter_install: true
mongodb_exporter_install: true
elasticsearch_exporter_install: true
proxy_exporter_install: true
```

Ensure that these exporters are deployed and running before proceeding with Grafana dashboards.

### 2. Secret for Authentication

This **stores the credentials** required for Prometheus to scrape Graylog metrics.

```yaml
---
kind: Secret
apiVersion: v1
metadata:
  name: graylog-admin-creds
stringData:
  username: prometheus
  password: prometheus
```

### 3. Prometheus Scrape Config

This **configures Prometheus** to scrape metrics from Graylog.

```yaml
---
apiVersion: monitoring.coreos.com/v1alpha1
kind: ScrapeConfig
metadata:
  name: graylog-scrape-config
spec:
  staticConfigs:
    - targets:
        - xx.xx.xx.xx:9999 #This is just an example of VM's IP addresses format
        - yy.yy.yy.yy:9999
        - zz.zz.zz.zz:9999
  scrapeInterval: 30s
  metricsPath: /metrics
  basicAuth:
    username:
      name: graylog-admin-creds
      key: username
    password:
      name: graylog-admin-creds
      key: password
```

---

## Monitoring

All **Logging VM** components that expose metrics are integrated with the monitoring system.
This means:
- Metrics are enabled and exposed in **Prometheus** format.
- ServiceMonitors/PodMonitors are created during deployment to integrate with Prometheus.

### Components with Metrics

- Graylog
- MongoDB
- OpenSearch

### Metrics

- **Graylog** → [Graylog Metrics Documentation](https://go2docs.graylog.org/5-0/interacting_with_your_log_data/metrics.html#PrometheusMetricExporting)
- **MongoDB** → [MongoDB Monitoring Docs](https://www.mongodb.com/docs/manual/administration/monitoring/)
- **OpenSearch** → [OpenSearch Metrics Docs](https://docs.opensearch.org/latest/monitoring-your-cluster/metrics/getting-started/)

---

## Dashboards

### Dashboard Management

- Dashboards are now included as part of the **external-logging-installer** because:
  - It **decouples dashboard lifecycle** from logging stack updates.
  - It **allows independent management** of dashboards without affecting the logging stack.
  - It is **easier to maintain and deploy** across multiple clusters.

### How to Use Dashboards in Grafana

1. Open **Grafana**.
2. Navigate to **Dashboards → Import**.
3. Paste the **JSON content** of the required dashboard.
4. Click **Import** to start using it.

### Available Dashboards:

- [Graylog Metrics Dashboard](/grafana/dashboards/monitoring/Graylog_(VM).json)
- [MongoDB Metrics Dashboard](/grafana/dashboards/monitoring/Graylog_(VM).json)
- [OpenSearch Metrics Dashboard](/grafana/dashboards/ElasticSearch_Summary_(VM).json)

---

## Logging

- Logs from **Graylog**, **MongoDB**, and **OpenSearch** are collected directly from the VM.
- The logs can be viewed via **Graylog** UI or **centralized logging storage**.

### Example Log Formats

#### Graylog (Text Format)

```bash
[2024-01-01T00:00:00,329][INFO] Successfully ensured index template gray_audit-template
[2024-01-01T00:00:01,292][INFO] Waiting for allocation of index <gray_audit_1>.
[2024-01-01T00:00:03,745][INFO] Index <gray_audit_1> has been successfully allocated.
```

#### MongoDB (JSON Format)

```json
{"t":{"$date":"2024-01-04T17:43:31.543+00:00"},"s":"I","c":"STORAGE","id":22430,"ctx":"Checkpointer","msg":"WiredTiger message","attr":{"message":"saving checkpoint snapshot min: 1554590, snapshot max: 1554590"}}
```

#### OpenSearch (Text Format)

```bash
[2024-01-04T17:50:58,716][INFO ][o.o.j.s.JobSweeper] [opensearch-0] Running full sweep
[2024-01-04T17:51:09,665][INFO ][sgaudit] [opensearch-0] {"audit_request_effective_user":"user","audit_trace_indices":["graylog_0"],"audit_request_origin":"REST"}
```

---

## Tracing

- **Graylog does not support Tracing.**
- No integration with **Jaeger** or **OpenTelemetry** is available.

---

## Profiler

- **Profiler is not supported** due to Graylog's **SSPL license** restrictions.

---
