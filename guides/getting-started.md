# Getting Started

This guide walks through deploying a Nova application to Fly.io from scratch.

## Prerequisites

- An Erlang/OTP project with rebar3
- A [Fly.io account](https://fly.io) with billing configured
- [`flyctl`](https://fly.io/docs/flyctl/install/) installed and authenticated

```bash
# Install flyctl
curl -L https://fly.io/install.sh | sh

# Authenticate
fly auth login
```

## 1. Add the plugin

Add `rebar3_fly` to your project plugins in `rebar.config`:

```erlang
{project_plugins, [
    rebar3_fly
]}.
```

## 2. Scaffold deployment files

```bash
rebar3 fly init
```

This creates:

- `Dockerfile` — multi-stage build for your OTP release
- `.dockerignore` — keeps the Docker context small
- `config/prod_sys.config` — Nova production configuration
- `config/vm.args` — BEAM VM arguments
- `fly.toml` — Fly.io app configuration

Existing files are never overwritten, so it's safe to run multiple times.

## 3. Add release configuration

The `init` command prints a `relx` snippet. Add it to your `rebar.config`:

```erlang
{relx, [
    {release, {my_app, "0.1.0"}, [
        my_app,
        sasl
    ]},
    {sys_config, "./config/prod_sys.config"},
    {vm_args, "./config/vm.args"},
    {mode, prod},
    {extended_start_script, true}
]}.
```

Add all your application dependencies to the release list (e.g., `nova`, `kura`, `bcrypt`).

## 4. Test the release locally

Before deploying, verify the release builds:

```bash
rebar3 release
_build/default/rel/my_app/bin/my_app foreground
```

## 5. Create the Fly app

```bash
fly launch --no-deploy
```

This creates the app on Fly.io and updates `fly.toml` with the app name. Choose your preferred region when prompted.

## 6. Deploy

```bash
rebar3 fly deploy
```

The plugin builds the Docker image locally and pushes it to Fly.io. Once deployed, your app is live at `https://<app-name>.fly.dev`.

## 7. Check status

```bash
rebar3 fly status
```

## Customizing the generated files

All generated files are meant as starting points. Common customizations:

### Dockerfile

- Add additional system packages if your NIFs need them
- Add `COPY assets ./assets` if you have static files outside `priv/`
- Adjust the builder image tag for a specific OTP version (e.g., `erlang:28.3`)

### fly.toml

- Change `primary_region` to your preferred region
- Adjust VM size and memory
- Add health checks for your application's endpoints
- Configure auto-scaling

### vm.args

- Change the cookie for production use (or use `fly secrets` to set it via env var)
- Adjust scheduler and async thread counts for your workload

## Next steps

- [Connecting to Fly Postgres](fly-postgres.md)
- [Production checklist](production-checklist.md)
