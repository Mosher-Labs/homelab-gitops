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

For an app that uses the OpenTelemetry SDK itself, use
`instrumentation.opentelemetry.io/inject-sdk: "opentelemetry/default"`. The
operator then injects only the `OTEL_*` environment (collector endpoint,
service name, resource attributes) and no agent. book-review-publisher works
this way.

The app then appears with `job="<namespace>/<service.name>"` (the service
name defaults to the workload name), and with `namespace` set to the app's
namespace rather than the collector's.

## Go is different

Go has no in-process agent, so prefer the SDK for Go apps we can change:
wrap the HTTP handler with `otelhttp`, export over OTLP/HTTP, and use
`inject-sdk`. Set `http.route` on the span from the matched route, or the
metrics have no route label.

For a Go binary we can't change, the operator can add an eBPF sidecar that
hooks the binary from outside. It has more requirements:

- **It doesn't work on nodes with kernel lockdown.** Secure Boot turns
  lockdown on (`/sys/kernel/security/lockdown` shows `[integrity]`), and the
  kernel then refuses `bpf_probe_write_user`
  ([go-instrumentation#290](https://github.com/open-telemetry/opentelemetry-go-instrumentation/issues/290)).
  battlestation has it on, hp-elitedesk doesn't. Pin the pod to a node
  without lockdown.
- The sidecar runs **privileged** (`CAP_SYS_ADMIN`, shared process
  namespace). It's scoped to the opted-in pod, but undoes that pod's
  hardening.
- The binary must keep its symbol table (no `-s`). Stripped Go 1.26+ binaries
  fail with `overflow in offset to read in the text section`
  ([go-instrumentation#3869](https://github.com/open-telemetry/opentelemetry-go-instrumentation/issues/3869)).
- For a Go version the agent has no cached offsets for (Go 1.27 in agent
  v0.24.0), it reads DWARF, so the binary must also keep it (no `-w`).
- A pod-level `runAsNonRoot: true` blocks the root sidecar; set it on the app
  container instead.
- It produces traces, not metrics. The collector's `spanmetrics` connector
  turns server spans into `http_server_request_duration_seconds`.
