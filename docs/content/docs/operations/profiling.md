---
title: Profiling
weight: 8
BookToC: true
---

# Profiling PAC Components

Pipelines-as-Code components embed the [Knative profiling server](https://pkg.go.dev/knative.dev/pkg/profiling),
which exposes Go runtime profiling data via the standard `net/http/pprof` endpoints.
Profiling is useful for diagnosing CPU hot-spots, memory growth, goroutine leaks, and
other performance issues.

## How It Works

Each PAC component starts an HTTP server on port **8008** (the default Knative profiling
port, overridable with the `PROFILING_PORT` environment variable). When profiling is
enabled the following endpoints are active:

| Endpoint | Description |
| --- | --- |
| `/debug/pprof/` | Index of all available profiles |
| `/debug/pprof/heap` | Heap memory allocations |
| `/debug/pprof/goroutine` | All current goroutines |
| `/debug/pprof/profile` | 30-second CPU profile |
| `/debug/pprof/trace` | Execution trace |
| `/debug/pprof/cmdline` | Process command line |
| `/debug/pprof/symbol` | Symbol lookup |

When profiling is disabled the server still listens but returns `404` for every request.

## Enabling Profiling

All components read profiling configuration from the same ConfigMap:

```bash
# Enable
kubectl patch configmap pipelines-as-code-config-observability \
  -n pipelines-as-code \
  --type merge \
  -p '{"data":{"runtime-profiling":"enabled"}}'

# Disable
kubectl patch configmap pipelines-as-code-config-observability \
  -n pipelines-as-code \
  --type merge \
  -p '{"data":{"runtime-profiling":"disabled"}}'
```

### Component-specific prerequisites

| Component | Extra step required |
| --- | --- |
| **watcher** | Set `PAC_DISABLE_HEALTH_PROBE=true` — otherwise a port conflict on 8080 causes the profiling server to shut down (see below). The watcher picks up ConfigMap changes without a restart. |
| **webhook** | Set `CONFIG_OBSERVABILITY_NAME=pipelines-as-code-config-observability` — the webhook Deployment does not set this by default and falls back to `config-observability`, which does not exist in the PAC namespace. The webhook picks up ConfigMap changes without a restart. |
| **controller** | **Profiling is not currently supported.** The eventing adapter framework used by the controller creates the pprof server but never starts it (`ListenAndServe` is never called), so port 8008 never opens. |

For the watcher:

```bash
kubectl set env deployment/pipelines-as-code-watcher \
  -n pipelines-as-code \
  PAC_DISABLE_HEALTH_PROBE=true
```

For the webhook:

```bash
kubectl set env deployment/pipelines-as-code-webhook \
  -n pipelines-as-code \
  CONFIG_OBSERVABILITY_NAME=pipelines-as-code-config-observability
```

## Accessing Profiles

The profiling server listens on port **8008** by default. If that conflicts with another
service, set `PROFILING_PORT` on the relevant Deployment(s) before proceeding:

```bash
kubectl set env deployment/pipelines-as-code-watcher \
  deployment/pipelines-as-code-webhook \
  -n pipelines-as-code \
  PROFILING_PORT=8090
```

Port 8008 (or your chosen port) is not declared in the container spec by default. Patch
the target Deployment(s) to expose it — substituting the port number if you changed it:

```bash
PROFILING_PORT=8008  # change if you set a custom port above
for deploy in pipelines-as-code-watcher pipelines-as-code-webhook; do
  kubectl patch deployment "$deploy" \
    -n pipelines-as-code \
    --type json \
    -p "[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/ports/-\",\"value\":{\"name\":\"profiling\",\"containerPort\":${PROFILING_PORT},\"protocol\":\"TCP\"}}]"
done
```

This triggers a rolling restart of the pod. Once the pod is running, you can access
the pprof endpoints.

### Using `kubectl port-forward`

The recommended way to access the profiling server is with `kubectl port-forward`. This
forwards a local port on your machine to the port on the pod, without exposing it to the
cluster network.

First, get the name of the pod you want to profile. Choose the label that matches the
component:

```bash
# Watcher
export POD_NAME=$(kubectl get pods -n pipelines-as-code \
  -l app.kubernetes.io/name=watcher \
  -o jsonpath='{.items[0].metadata.name}')

# Webhook
export POD_NAME=$(kubectl get pods -n pipelines-as-code \
  -l app.kubernetes.io/name=webhook \
  -o jsonpath='{.items[0].metadata.name}')
```

Then, forward a local port to the pod's profiling port (adjust if you changed `PROFILING_PORT`):

```bash
kubectl port-forward -n pipelines-as-code $POD_NAME 8008:8008
```

The pprof index is now available at `http://localhost:8008/debug/pprof/`.

### Capturing profiles with `go tool pprof`

With `kubectl port-forward` running, use `go tool pprof` to analyze profiles directly:

```bash
# Heap profile
go tool pprof http://localhost:8008/debug/pprof/heap

# 30-second CPU profile
go tool pprof http://localhost:8008/debug/pprof/profile

# Goroutine dump
go tool pprof http://localhost:8008/debug/pprof/goroutine
```

### Saving profiles to disk

You can also save profiles to disk for later analysis using `curl`:

```bash
# Save a heap profile
curl -o heap-$(date +%Y%m%d-%H%M%S).pb.gz \
  http://localhost:8008/debug/pprof/heap

# Analyze later - CLI
go tool pprof heap-<timestamp>.pb.gz

# Analyze later - interactive web UI (opens browser at http://localhost:8009)
go tool pprof -http=:8009 heap-<timestamp>.pb.gz
```

## Security Considerations

The profiling server exposes internal runtime data. Because port 8008 is not declared
in the container spec by default, access requires an explicit Deployment patch, limiting
it to users with `deployments/patch` permission in the `pipelines-as-code` namespace.

Do not expose port 8008 via a Service or Ingress in production environments. Disable
profiling (`runtime-profiling: "disabled"`) when not actively investigating an issue.
