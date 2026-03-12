# Changelog

## [0.1.0]

### Added

- `rebar3 fly init` — scaffolds all deployment files:
  - `Dockerfile` with multi-stage build (correct GLIBC for OTP 28+)
  - `.dockerignore`
  - `config/prod_sys.config` (Nova production config)
  - `config/vm.args` (BEAM VM arguments)
  - `fly.toml` (Fly.io app configuration)
- `rebar3 fly deploy` — builds locally and deploys to Fly.io
- `rebar3 fly status` — shows Fly.io app status
- `.tool-versions` integration for Docker build args
- IPv6 guidance for Fly Postgres connectivity
- Guides: Getting Started, Fly Postgres, Production Checklist
