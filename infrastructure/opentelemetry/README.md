# opentelemetry

The OpenTelemetry Operator (`infrastructure/opentelemetry-operator`) injects
agents into pods that opt in, and the collector here turns what they send
into request metrics for the observability module's APM alerts and Services
row. This is for apps we can't change; an app we can change should use the
OpenTelemetry SDK or a `/metrics` endpoint instead.

## Opting an app in

Add annotations to the pod template:

| Language | Annotations |
| --- | --- |
| Go | `instrumentation.opentelemetry.io/inject-go: "opentelemetry/default"` and `instrumentation.opentelemetry.io/otel-go-auto-target-exe: <path to the binary>` |
| Node.js | `instrumentation.opentelemetry.io/inject-nodejs: "opentelemetry/default"` |
| Python | `instrumentation.opentelemetry.io/inject-python: "opentelemetry/default"` |
| Java | `instrumentation.opentelemetry.io/inject-java: "opentelemetry/default"` |

The app then appears under its `service.name` (by default the workload name)
as the `job` label.

## Go is different

Go has no in-process agent. The operator adds an eBPF sidecar that hooks the
binary from outside, which means:

- The sidecar runs **privileged** (`CAP_SYS_ADMIN`, shared process
  namespace). It's scoped to the opted-in pod, but undoes that pod's
  hardening.
- The binary must keep its symbol table: build without `-ldflags=-s`
  (`-w` is fine). A stripped third-party binary can't be instrumented.
- A pod-level `runAsNonRoot: true` blocks the root sidecar; set it on the app
  container instead.
- The agent supports a range of Go versions; a binary built with a newer Go
  than the agent knows may not be hooked.
- It produces traces, not metrics. The collector's `spanmetrics` connector
  turns server spans into `http_server_request_duration_seconds`.
