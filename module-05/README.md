# Module 05 — Observability & Troubleshooting

Prometheus, Grafana, Loki, Alloy, and Alertmanager run on the lab k3s cluster. Grafana provides two dashboards.

- Student Namespace Node Load** shows CPU usage, memory usage, and running Pod count by node and student namespace.
- Kyverno Root Filesystem Audit** shows readOnlyRootFilesystem audit failures with the affected Pod and reason. An adapter writes Kyverno events to a dedicated Pod's log, and Alloy forwards those logs to Loki.

Verification: A test Pod in student01 produced CPU and memory metrics. Its audit failure appeared in Loki and triggered KyvernoReadOnlyRootFilesystemAuditFailed in Alertmanager. Alerts are visible in Alertmanager.
