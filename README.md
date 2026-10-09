# lowfat-plugins

Community plugins for [`lowfat`](https://github.com/zdk/lowfat) — each one compresses a tool's output to save LLM context.

## Quickstart

Install `lowfat` 0.9.0 or newer first ([how](https://github.com/zdk/lowfat#install)), then:

```sh
# Clone every plugin into lowfat's scan directory
git clone https://github.com/zdk/lowfat-plugins.git ~/.config/lowfat/plugins

# Use them — installed plugins are active immediately
lowfat terraform plan
lowfat helm status my-release
```

You'll see noticeably less output than running those commands directly. To wrap commands automatically, add to your shell config:

```sh
eval "$(lowfat shell-init zsh)"   # or bash
```

## Available plugins

Savings are at the **default** `full` level; real-world numbers are usually higher (see [caveats](#about-the-savings)).

### Cloud & infrastructure

| Plugin                                             | Wraps                         | Savings |
| -------------------------------------------------- | ----------------------------- | ------- |
| [`aws-compact`](aws/aws-compact)                   | `aws`                         | −38%    |
| [`ansible-compact`](ansible/ansible-compact)       | `ansible-playbook`, `ansible` | −23%    |
| [`helm-compact`](helm/helm-compact)                | `helm`                        | −51%    |
| [`kubectl-compact`](kubectl/kubectl-compact)       | `kubectl`, `k`                | −33%    |
| [`terraform-compact`](terraform/terraform-compact) | `terraform`, `tf`             | −47%    |

### Version control

| Plugin                             | Wraps      | Savings |
| ---------------------------------- | ---------- | ------- |
| [`git-compact`](git/git-compact) † | `git`, `g` | −25%    |

### Language ecosystems

| Plugin                                    | Wraps               | Savings |
| ----------------------------------------- | ------------------- | ------- |
| [`cargo-compact`](cargo/cargo-compact)    | `cargo`             | −51%    |
| [`go-compact`](go/go-compact)             | `go`                | −29%    |
| [`npm-compact`](npm/npm-compact)          | `npm`               | −62%    |
| [`pytest-compact`](pytest/pytest-compact) | `pytest`, `py.test` | −36%    |

### Network & data

| Plugin                              | Wraps  | Savings |
| ----------------------------------- | ------ | ------- |
| [`curl-compact`](curl/curl-compact) | `curl` | −82%    |
| [`psql-compact`](psql/psql-compact) | `psql` | −41%    |

† `git-compact` is also bundled inside lowfat (covering `status` / `log` / `diff` / `show`). The community version adds network ops (`push`, `pull`, `fetch`, `clone`) and edit commands (`add`, `commit`, `reset`, `restore`, `stash`, `tag`).

**Shorthands** (`k`, `tf`, `g`) work even though they aren't real binaries — lowfat reads the plugin's `bin` field and routes `lowfat k get pods` to `kubectl`.

## Trust: overriding bundled plugins

Installed plugins are active right away. `trust` matters in **one** case: when a community plugin overlaps a plugin bundled inside lowfat (`docker`, `ls`, `find`, `grep`, `tree`, `git`). Trust decides which wins for the shared commands.

```sh
lowfat plugin trust git-compact     # community version wins its overlaps
lowfat plugin untrust git-compact   # fall back to the bundled version
```

The choice is saved to `~/.config/lowfat/trusted.toml` (one community-plugin name per line). Plugins that don't overlap a built-in — `terraform-compact`, `helm-compact`, `kubectl-compact`, … — work whether or not they're listed.

Inspect what lowfat sees:

```sh
lowfat plugin list           # all plugins (community + bundled)
lowfat plugin doctor         # same + parse/dependency check + rule count
lowfat plugin info <name>    # path, version, commands for one plugin
```

## Intensity levels

```sh
lowfat level ultra   # most compression — verdicts only
lowfat level full    # default — keeps detail, strips noise
lowfat level lite    # mild — most output preserved
lowfat level         # show current level
```

| Level              | Best for                                               | Typical savings |
| ------------------ | ------------------------------------------------------ | --------------- |
| `lite`             | Local dev where you want to see almost everything      | −0–30%          |
| `full` _(default)_ | Day-to-day LLM context — strips noise, keeps signal    | −20–60%         |
| `ultra`            | Agent loops where you just need "did it work?"         | −70–95%         |

Override per-run with `LOWFAT_LEVEL=ultra lowfat terraform plan`.

**Failure is always safe.** Every plugin passes a failed command through raw, with `if exit failed: raw` or a `rule` that has `exit: failed`. So when a command fails you get the full error — compile errors, terraform diagnostics, pytest tracebacks — even at `ultra`.

## Troubleshooting

**Nothing happens** when I run `lowfat <cmd>` — the plugin probably isn't in lowfat's scan dir. Check `lowfat plugin doctor`; if missing, clone or move it into `~/.config/lowfat/plugins/`. Also note `full` passes many subcommands through nearly unchanged — try `LOWFAT_LEVEL=ultra` to see the filter work.

**Two plugin directories** — you have plugins in both `~/.lowfat` and `~/.config/lowfat`. Move everything to `~/.config/lowfat/plugins/` and delete the old `~/.lowfat/`.

**Wrong plugin runs** — a community plugin overlaps a built-in (usually `git-compact`). Run `lowfat plugin info git-compact`, then `trust`/`untrust` to pick the winner (see [Trust](#trust-overriding-bundled-plugins)).

**Preview a filter without running the command** — pipe a sample through it; `--explain` prints per-stage diagnostics to stderr:

```sh
cat samples/helm-install-full.txt \
  | lowfat filter helm/helm-compact/filter.lf --sub=install --explain
```

## About the savings

The table percentages come from `lowfat plugin bench <name>` against each plugin's `samples/*.txt` at `full`. They **under**-represent real savings because:

1. **Samples are small** (30–100 lines), so `head N` rarely fires. Unbounded `git log` or a full `helm status` see −60–90%.
2. **Bench assumes exit 0**, skipping the `if exit failed:` branches where filters do much of their work.
3. `ultra` **is far more aggressive** — collapsing a successful run to one status line.

Measure your own:

```sh
helm install my-app ./chart > /tmp/helm-real.txt
wc -c /tmp/helm-real.txt
cat /tmp/helm-real.txt | lowfat filter ~/.config/lowfat/plugins/helm/helm-compact/filter.lf --sub=install | wc -c
```

## Writing your own plugin

Scaffold with `lowfat plugin new <category>/<name>`, or copy an existing folder. Each plugin is three things:

```
my-tool/my-tool-compact/
├── lowfat.toml     # name, version, commands it wraps
├── filter.lf       # the rules
└── samples/*.txt   # captured output for `lowfat plugin bench`
```

### Rules

A `filter.lf` file is a list of named rules. lowfat runs the first rule whose
fields all hold. Needs lowfat 0.9.0 or newer.

```
# A failed command keeps its full error output.
rule failed:
    exit: failed
    do: raw

rule build:
    sub: build|check
    do:
        match level:
            ultra:
                keep /(error|warning)/
                head 30
                or "mytool build: ok"
            else:
                drop /^Compiling /
                head 80

rule other:
    do: head 40
```

The full guide is in [docs/DSL.md](docs/DSL.md): fields, ops, levels, macros,
JSON output and how to test.

**Please keep the failure rule.** Start every file with a rule that has
`exit: failed`, so agents get the full error when things break. PRs that
filter the failure path will be asked to add it.

## Contributing

PRs welcome for:

- **New plugins** for uncovered tools (helm-diff, golangci-lint, pnpm, yarn, redis-cli, …)
- **More samples** for existing plugins — bigger/more diverse samples push bench numbers up
- **Filter improvements** — tighten regexes or `head N` budgets where `full`-level savings are weak

Run `lowfat plugin bench <name>` before and after your change, and include the numbers in the PR.
