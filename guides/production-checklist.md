# Production Checklist

Things to consider before running your Erlang/OTP app on Fly.io in production.

## Security

### Cookie

The generated `vm.args` uses a predictable cookie (`<app_name>_cookie`). For production, set the cookie via an environment variable:

```
# vm.args
-setcookie ${RELEASE_COOKIE}
```

```bash
fly secrets set RELEASE_COOKIE=$(openssl rand -hex 32)
```

### Secrets

Never hardcode credentials. Use `fly secrets` for all sensitive values:

```bash
fly secrets set SECRET_KEY_BASE=$(openssl rand -hex 64)
fly secrets set DATABASE_URL=postgres://...
```

Access them in your app with `os:getenv/1`.

## Dockerfile

### Pin your OTP version

The generated Dockerfile uses `erlang:28` which tracks the latest patch. For reproducible builds, pin to a specific version:

```dockerfile
FROM erlang:28.3.1 AS builder
```

Or use `.tool-versions` — the plugin passes `ERLANG_VERSION` as a build arg:

```dockerfile
ARG ERLANG_VERSION=28
FROM erlang:${ERLANG_VERSION} AS builder
```

### NIF dependencies

If your app uses NIFs (like `bcrypt`), the C compiler and headers are already available in the `erlang` builder image. However, if your NIFs link against system libraries, you may need to install them in the runtime stage too.

## Fly.io configuration

### Region

The generated `fly.toml` defaults to `arn` (Stockholm). Change `primary_region` to the region closest to your users:

```toml
primary_region = 'iad'  # Ashburn, Virginia
```

See all regions with `fly platform regions`.

### Scaling

By default, machines auto-stop when idle and auto-start on requests. For always-on:

```toml
[http_service]
  min_machines_running = 1
```

To add more machines:

```bash
fly scale count 2
```

### Memory

The default 1 GB is fine for most Erlang apps. The BEAM is memory-efficient. Monitor usage and adjust:

```bash
fly scale memory 512  # or 2048, etc.
```

### Health checks

Add health check endpoints to your Nova router:

```erlang
routes(_Environment) ->
    [
        #{
            prefix => "",
            security => false,
            routes => [
                {"/healthz", fun health_controller:liveness/1, #{methods => [get]}},
                {"/readyz", fun health_controller:readiness/1, #{methods => [get]}}
            ]
        }
    ].
```

Then configure them in `fly.toml`:

```toml
[checks]
  [checks.health]
    grace_period = "10s"
    interval = "15s"
    method = "GET"
    path = "/healthz"
    port = 8080
    timeout = "5s"
    type = "http"
```

## Database

### Backups

Fly's unmanaged Postgres does not include automatic backups. Set up your own:

```bash
# Manual snapshot
fly postgres backup create --app my-app-db

# Or use pg_dump via proxy
fly proxy 15432:5432 --app my-app-db &
pg_dump -h localhost -p 15432 -U postgres my_app > backup.sql
```

### Migrations

Run migrations on app startup (as shown in the kura example) or before deploy:

```bash
fly ssh console --app my-app -C "/app/bin/my_app eval 'my_app_repo:start(), kura_migrator:migrate(my_app_repo)'"
```

## Monitoring

### Logs

```bash
fly logs --app my-app
```

### Metrics

Fly provides basic metrics at `https://fly.io/apps/my-app/monitoring`.

For more detailed observability, add [OpenTelemetry](https://opentelemetry.io/) to your app and export to a collector.

## Erlang distribution

If you scale to multiple machines and want them to form an Erlang cluster, you'll need to:

1. Use `fly-replay` headers or Fly's internal DNS for node discovery
2. Configure `epmd` or use `-dist_listen false` with custom distribution
3. Set the same cookie across all nodes

This is an advanced topic — for most web apps, a single machine with auto-scaling is sufficient.
