-module(rebar3_fly_prv).

-export([init/1, do/1, format_error/1]).

-define(PROVIDER, fly).
-define(DEPS, []).

-spec init(term()) -> {ok, term()}.
init(State) ->
    Provider = providers:create([
        {name, ?PROVIDER},
        {module, ?MODULE},
        {bare, false},
        {deps, ?DEPS},
        {example, "rebar3 fly deploy"},
        {opts, [
            {action, undefined, undefined, string, "Action: init, launch, deploy, or status"}
        ]},
        {short_desc, "Deploy Erlang/OTP application to Fly.io"},
        {desc,
            "Manage Fly.io deployments for Erlang/OTP applications.\n\n"
            "Actions:\n"
            "  init    - Scaffold Fly.io deployment files (Dockerfile, release config, fly.toml)\n"
            "  launch  - Create the app on Fly.io (first time setup)\n"
            "  deploy  - Build and deploy to Fly.io\n"
            "  status  - Show app status on Fly.io\n"}
    ]),
    {ok, rebar_state:add_provider(State, Provider)}.

-spec do(term()) -> {ok, term()} | {error, string()}.
do(State) ->
    {Args, _} = rebar_state:command_parsed_args(State),
    Action = proplists:get_value(action, Args),
    AppName = get_app_name(State),
    AppDir = get_app_dir(State),
    run_action(Action, AppName, AppDir, State).

-spec format_error(any()) -> iolist().
format_error(Reason) ->
    io_lib:format("~p", [Reason]).

%%--------------------------------------------------------------------
%% Actions
%%--------------------------------------------------------------------

run_action("init", AppName, AppDir, State) ->
    fly_init(AppName, AppDir, State);
run_action("launch", _AppName, AppDir, State) ->
    ensure_flyctl(),
    fly_launch(AppDir, State);
run_action("deploy", _AppName, AppDir, State) ->
    ensure_flyctl(),
    fly_deploy(AppDir, State);
run_action("status", _AppName, _AppDir, State) ->
    ensure_flyctl(),
    fly_status(State);
run_action(undefined, _AppName, AppDir, State) ->
    ensure_flyctl(),
    fly_deploy(AppDir, State);
run_action(Other, _AppName, _AppDir, _State) ->
    rebar_api:abort("Unknown action: ~s. Use init, launch, deploy, or status.", [Other]).

%%--------------------------------------------------------------------
%% Init — scaffold all deployment files
%%--------------------------------------------------------------------

fly_init(AppName, AppDir, State) ->
    NameStr = atom_to_list(AppName),
    OtpMajor = otp_major_version(),
    Files = [
        {"Dockerfile", filename:join(AppDir, "Dockerfile"), generate_dockerfile(NameStr, OtpMajor)},
        {".dockerignore", filename:join(AppDir, ".dockerignore"), generate_dockerignore()},
        {"config/prod_sys.config", filename:join([AppDir, "config", "prod_sys.config"]),
            generate_prod_sys_config(NameStr)},
        {"config/vm.args", filename:join([AppDir, "config", "vm.args"]), generate_vm_args(NameStr)},
        {"fly.toml", filename:join(AppDir, "fly.toml"), generate_fly_toml(NameStr)}
    ],
    Generated = lists:filtermap(
        fun({Label, Path, Content}) ->
            case maybe_write_file(Path, Content) of
                {_, created} -> {true, Label};
                {_, exists} -> false
            end
        end,
        Files
    ),
    case Generated of
        [] ->
            rebar_api:info("All deployment files already exist.", []);
        _ ->
            rebar_api:info("Created: ~s", [string:join(Generated, ", ")])
    end,
    rebar_api:info("", []),
    print_relx_snippet(NameStr),
    print_ipv6_note(),
    print_next_steps(),
    {ok, State}.

%%--------------------------------------------------------------------
%% Launch — create app on Fly.io (first time)
%%--------------------------------------------------------------------

fly_launch(AppDir, State) ->
    rebar_api:info("Launching app on Fly.io...", []),
    Cmd = ["fly launch --no-deploy --copy-config --path ", AppDir],
    require_cmd(Cmd, "fly launch"),
    rebar_api:info("App created! Now run: rebar3 fly deploy", []),
    {ok, State}.

%%--------------------------------------------------------------------
%% Deploy
%%--------------------------------------------------------------------

fly_deploy(AppDir, State) ->
    rebar_api:info("Deploying to Fly.io...", []),
    ToolVersions = filename:join(AppDir, ".tool-versions"),
    BuildArgs = build_args_from_tool_versions(ToolVersions),
    Cmd = ["fly deploy ", AppDir, " --local-only", BuildArgs],
    require_cmd(Cmd, "fly deploy"),
    rebar_api:info("Deploy complete!", []),
    {ok, State}.

%%--------------------------------------------------------------------
%% Status
%%--------------------------------------------------------------------

fly_status(State) ->
    require_cmd("fly status", "fly status"),
    {ok, State}.

%%--------------------------------------------------------------------
%% File generators
%%--------------------------------------------------------------------

generate_dockerfile(AppName, OtpMajor) ->
    RuntimeImage = runtime_image(OtpMajor),
    [
        "FROM erlang:",
        integer_to_list(OtpMajor),
        " AS builder\n",
        "\n",
        "WORKDIR /app\n",
        "\n",
        "RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*\n",
        "\n",
        "COPY rebar.config rebar.lock ./\n",
        "RUN rebar3 compile\n",
        "\n",
        "COPY config ./config\n",
        "COPY src ./src\n",
        "COPY priv ./priv\n",
        "\n",
        "RUN rebar3 release\n",
        "\n",
        "FROM ",
        RuntimeImage,
        "\n",
        "\n",
        "RUN apt-get update && \\\n",
        "    apt-get install -y --no-install-recommends \\\n",
        "    libssl3 libncurses6 libstdc++6 && \\\n",
        "    rm -rf /var/lib/apt/lists/*\n",
        "\n",
        "WORKDIR /app\n",
        "\n",
        "COPY --from=builder /app/_build/default/rel/",
        AppName,
        " ./\n",
        "\n",
        "ENV PORT=8080\n",
        "EXPOSE 8080\n",
        "\n",
        "CMD [\"bin/",
        AppName,
        "\", \"foreground\"]\n"
    ].

generate_dockerignore() ->
    [
        "_build\n",
        ".git\n",
        "erl_crash.dump\n",
        "rebar3.crashdump\n",
        "*.beam\n"
    ].

generate_prod_sys_config(AppName) ->
    [
        "[\n",
        " {nova, [\n",
        "         {environment, prod},\n",
        "         {cowboy_configuration, #{\n",
        "                                  port => 8080\n",
        "                                 }},\n",
        "         {bootstrap_application, ",
        AppName,
        "}\n",
        "        ]}\n",
        "].\n"
    ].

generate_vm_args(AppName) ->
    [
        "-name ",
        AppName,
        "@127.0.0.1\n",
        "-setcookie ",
        AppName,
        "_cookie\n",
        "+K true\n",
        "+A 30\n"
    ].

generate_fly_toml(AppName) ->
    [
        "app = '",
        AppName,
        "'\n",
        "primary_region = 'arn'\n",
        "\n",
        "[build]\n",
        "\n",
        "[http_service]\n",
        "  internal_port = 8080\n",
        "  force_https = true\n",
        "  auto_stop_machines = 'stop'\n",
        "  auto_start_machines = true\n",
        "  min_machines_running = 0\n",
        "  processes = ['app']\n",
        "\n",
        "[[vm]]\n",
        "  memory = '1gb'\n",
        "  cpu_kind = 'shared'\n",
        "  cpus = 1\n"
    ].

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------

runtime_image(OtpMajor) when OtpMajor >= 28 ->
    "debian:trixie-slim";
runtime_image(_) ->
    "debian:bookworm-slim".

otp_major_version() ->
    list_to_integer(erlang:system_info(otp_release)).

get_app_info(State) ->
    case rebar_state:project_apps(State) of
        [Hd | _] ->
            {binary_to_atom(rebar_app_info:name(Hd)), rebar_app_info:dir(Hd)};
        [] ->
            Dir = rebar_dir:root_dir(State),
            case find_app_src(Dir) of
                {ok, Name} ->
                    {Name, Dir};
                error ->
                    {list_to_atom(filename:basename(Dir)), Dir}
            end
    end.

get_app_name(State) ->
    {Name, _} = get_app_info(State),
    Name.

get_app_dir(State) ->
    {_, Dir} = get_app_info(State),
    Dir.

find_app_src(Dir) ->
    SrcDir = filename:join(Dir, "src"),
    case filelib:wildcard("*.app.src", SrcDir) of
        [AppSrc | _] ->
            BaseName = filename:basename(AppSrc, ".app.src"),
            {ok, list_to_atom(BaseName)};
        [] ->
            error
    end.

ensure_flyctl() ->
    case os:find_executable("fly") of
        false ->
            rebar_api:abort(
                "flyctl not found. Install it: curl -L https://fly.io/install.sh | sh", []
            );
        _Path ->
            ok
    end.

maybe_write_file(Path, Content) ->
    case filelib:is_regular(Path) of
        true ->
            {Path, exists};
        false ->
            ok = filelib:ensure_dir(Path),
            ok = file:write_file(Path, Content),
            {Path, created}
    end.

print_relx_snippet(AppName) ->
    rebar_api:info(
        "Add this to your rebar.config if you don't have a relx section:\n"
        "\n"
        "{relx, [\n"
        "    {release, {~s, \"0.1.0\"}, [\n"
        "        ~s,\n"
        "        sasl\n"
        "    ]},\n"
        "    {sys_config, \"./config/prod_sys.config\"},\n"
        "    {vm_args, \"./config/vm.args\"},\n"
        "    {mode, prod},\n"
        "    {extended_start_script, true}\n"
        "]}.\n",
        [AppName, AppName]
    ).

print_ipv6_note() ->
    rebar_api:info(
        "NOTE: Fly.io uses IPv6 for internal networking.\n"
        "If connecting to Fly Postgres, pass [inet6] as a socket option\n"
        "to your database driver (e.g. pgo socket_options).\n",
        []
    ).

print_next_steps() ->
    rebar_api:info(
        "Next steps:\n"
        "  1. Add the relx config above to rebar.config\n"
        "  2. Run: rebar3 fly launch (first time only)\n"
        "  3. Run: rebar3 fly deploy\n"
        "  4. (Optional) Create Postgres: fly postgres create\n"
        "  5. (Optional) Attach DB: fly postgres attach <db-name>\n",
        []
    ).

require_cmd(Cmd, Label) ->
    case run_cmd(Cmd) of
        0 -> ok;
        Code -> rebar_api:abort("~s failed with exit code ~p", [Label, Code])
    end.

build_args_from_tool_versions(ToolVersions) ->
    case file:read_file(ToolVersions) of
        {ok, Bin} ->
            Lines = string:split(binary_to_list(Bin), "\n", all),
            lists:flatmap(fun tool_version_to_arg/1, Lines);
        {error, _} ->
            []
    end.

tool_version_to_arg(Line) ->
    case string:tokens(string:trim(Line), " ") of
        ["erlang", Vsn] ->
            [" --build-arg ERLANG_VERSION=", Vsn];
        ["rebar", Vsn] ->
            [" --build-arg REBAR_VERSION=", Vsn];
        _ ->
            []
    end.

run_cmd(Cmd) ->
    Port = open_port({spawn, lists:flatten(Cmd)}, [
        exit_status, binary, stderr_to_stdout, {line, 1024}
    ]),
    collect_port_output(Port).

collect_port_output(Port) ->
    receive
        {Port, {data, {_, Line}}} ->
            rebar_api:info("~s", [Line]),
            collect_port_output(Port);
        {Port, {exit_status, Status}} ->
            Status
    end.
