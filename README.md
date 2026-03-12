# rebar3_fly

A rebar3 plugin for deploying Erlang/OTP applications to [Fly.io](https://fly.io).

Scaffolds all the files you need for a production deployment — Dockerfile, release config, fly.toml — and handles the deploy.

## Installation

Add to your `rebar.config`:

```erlang
{project_plugins, [
    rebar3_fly
]}.
```

You also need [`flyctl`](https://fly.io/docs/flyctl/install/) installed:

```bash
curl -L https://fly.io/install.sh | sh
```

## Quick start

```bash
# Scaffold deployment files
rebar3 fly init

# Create the Fly app
fly launch --no-deploy

# (Optional) Create and attach Postgres
fly postgres create --name myapp-db --region arn
fly postgres attach myapp-db

# Deploy
rebar3 fly deploy
```

## Commands

### `rebar3 fly init`

Generates all files needed for a Fly.io deployment:

| File | Purpose |
|------|---------|
| `Dockerfile` | Multi-stage build with OTP release |
| `.dockerignore` | Excludes `_build`, `.git`, crash dumps |
| `config/prod_sys.config` | Nova production config |
| `config/vm.args` | BEAM VM arguments |
| `fly.toml` | Fly.io app configuration |

Existing files are never overwritten.

After running, add the printed `relx` config to your `rebar.config`.

### `rebar3 fly deploy`

Builds the Docker image locally and deploys to Fly.io.

If a `.tool-versions` file exists, the `erlang` and `rebar` versions are passed as Docker build args (`ERLANG_VERSION`, `REBAR_VERSION`).

### `rebar3 fly status`

Shows the current status of your Fly.io app.

## What it generates

### Dockerfile

A multi-stage Dockerfile that:

1. **Builder stage** — uses the official `erlang` Docker image, compiles deps first (cached layer), then copies source and builds a release
2. **Runtime stage** — minimal Debian image with only the libraries needed to run ERTS

The runtime image is automatically selected based on your OTP version:

| OTP version | Runtime image |
|-------------|---------------|
| 28+ | `debian:trixie-slim` |
| < 28 | `debian:bookworm-slim` |

This matters because OTP 28 requires GLIBC 2.38+, which is only available in Debian Trixie.

### fly.toml

Default configuration:

- Region: `arn` (Stockholm)
- VM: `shared-cpu-1x`, 1 GB RAM
- Internal port: 8080 (HTTPS enforced)
- Auto-stop/start machines enabled

## Fly.io and IPv6

Fly.io uses IPv6 for internal networking. If your app connects to Fly Postgres, you need to pass `inet6` as a socket option to your database driver.

For example, with [kura](https://github.com/novaframework/kura) (which uses pgo):

```erlang
config() ->
    #{
        pool => my_repo,
        hostname => <<"my-db.internal">>,
        port => 5433,
        database => <<"my_app">>,
        username => <<"postgres">>,
        password => <<"secret">>,
        pool_size => 10,
        socket_options => [inet6]
    }.
```

Or parse `DATABASE_URL` from the environment (set automatically by `fly postgres attach`):

```erlang
init(Config) ->
    case os:getenv("DATABASE_URL") of
        false -> Config;
        Url -> parse_database_url(Url)
    end.
```

See the [Fly Postgres guide](guides/fly-postgres.md) for a complete example.

## License

MIT
