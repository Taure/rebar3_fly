# Connecting to Fly Postgres

Fly.io provides unmanaged Postgres instances that run alongside your app in the same private network. This guide covers setting up and connecting to Fly Postgres from an Erlang/OTP application.

## Create a Postgres instance

```bash
fly postgres create --name my-app-db --region arn --vm-size shared-cpu-1x --volume-size 1
```

Save the credentials printed after creation — you won't see them again.

## Attach to your app

```bash
fly postgres attach my-app-db --app my-app
```

This automatically:
- Creates a database and user for your app
- Sets `DATABASE_URL` as a secret on your app

## The IPv6 problem

Fly.io uses IPv6 for all internal networking. The `DATABASE_URL` uses `.flycast` or `.internal` hostnames that resolve to IPv6 addresses.

Most Erlang PostgreSQL drivers (like [pgo](https://github.com/erleans/pgo)) use `gen_tcp:connect/3` which defaults to IPv4. You must pass the `inet6` socket option to connect over IPv6.

## Configuring your repo

### With kura

If you use [kura](https://github.com/novaframework/kura), add `socket_options` to your repo config:

```erlang
-module(my_repo).
-behaviour(kura_repo).

-export([otp_app/0, init/1]).

otp_app() -> my_app.

init(Config) ->
    case os:getenv("DATABASE_URL") of
        false ->
            maps:merge(#{
                pool => my_repo,
                database => <<"my_app_dev">>,
                hostname => <<"localhost">>,
                port => 5432,
                username => <<"postgres">>,
                password => <<"postgres">>,
                pool_size => 10
            }, Config);
        Url ->
            parse_database_url(Url)
    end.

parse_database_url(Url) ->
    #{
        scheme := <<"postgres", _/binary>>,
        host := Host,
        path := Path,
        userinfo := UserInfo
    } = Map = uri_string:parse(list_to_binary(Url)),
    [Username, Password] = binary:split(UserInfo, <<":">>),
    <<"/", Database/binary>> = Path,
    Port = maps:get(port, Map, 5432),
    #{
        pool => my_repo,
        hostname => Host,
        port => Port,
        database => Database,
        username => Username,
        password => Password,
        pool_size => 10,
        socket_options => [inet6]
    }.
```

The key line is `socket_options => [inet6]` — without this, the connection will fail with `{error, none_available}` or `{error, nxdomain}`.

> **Note:** kura requires the `socket_options` feature from the `feat/socket-options` branch or version 1.4.0+.

### With pgo directly

If you're using pgo without kura:

```erlang
pgo:start_pool(my_pool, #{
    host => "my-app-db.internal",
    port => 5433,
    database => "my_app",
    user => "postgres",
    password => "secret",
    pool_size => 10,
    socket_options => [inet6]
}).
```

## Port numbers

Fly Postgres exposes two ports:

| Port | Protocol | Use |
|------|----------|-----|
| 5432 | Proxy (pgbouncer) | `.flycast` hostnames |
| 5433 | Direct Postgres | `.internal` hostnames |

The `DATABASE_URL` from `fly postgres attach` uses port 5432 with `.flycast`. Both work — the proxy adds connection pooling at the Fly level.

## Verifying the connection

SSH into your running app to test:

```bash
fly ssh console --app my-app

# Inside the machine
/app/bin/my_app remote

# In the Erlang shell
> my_repo:query("SELECT 1", []).
#{command => select, rows => [#{...}]}
```

## Troubleshooting

### `{error, none_available}`

The pgo pool couldn't establish any connections. Common causes:

1. **Missing `inet6`** — add `socket_options => [inet6]` to your pool config
2. **Wrong hostname** — use `.internal` (port 5433) or `.flycast` (port 5432)
3. **Postgres not running** — check with `fly status --app my-app-db`

### `{error, nxdomain}`

DNS resolution failed. The `.internal` and `.flycast` hostnames only resolve inside the Fly private network, not from your local machine.

### Connection works locally but not on Fly

Your local Postgres uses IPv4 on localhost. On Fly, everything is IPv6. Make sure your config branches: use `inet6` only when `DATABASE_URL` is set (i.e., on Fly), and omit it locally.
