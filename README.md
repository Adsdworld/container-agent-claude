# container-agent-claude

[![Image](https://github.com/Adsdworld/container-agent-claude/actions/workflows/image.yml/badge.svg?branch=main)](https://github.com/Adsdworld/container-agent-claude/actions/workflows/image.yml)

A standard container that runs an autonomous Claude Code agent at a fixed
interval, once a day by default.

You give it two things: a **bible** (its rules) and its **MCP servers**. It gets
a writable directory where it keeps its own scripts, guidelines and state. The
image is generic: what the agent does is entirely defined by the files you mount.

## What is in the image

- Debian 13 (slim), Python 3 with `pip`, `venv`, `requests` and `yaml`
- `curl`, `wget`, `jq`, `git`, `sqlite3`, `unzip`
- Claude Code, running headless as `root` inside the container
- `cron`, which starts the agent's own scripts on their schedule

## Layout

```
/agent/config/          mounted read-only, written by you
├── bible.md            the agent's rules, added to its system prompt on every run (required)
├── mcp.json            its MCP servers, in Claude Code's .mcp.json format (optional)
├── environment         variables for the agent and its scripts, as NAME=value lines (optional)
└── prompt.md           replaces the default start-of-run prompt (optional)

/agent/data/            mounted read-write, owned by the agent
├── inbox/              messages you leave for the agent, with their git history;
│                       answered ones go to done/
├── scripts/            programs the agent writes for itself, with their git history
├── CLAUDE.md           guidelines the agent writes for itself, loaded by Claude Code
├── crontab             the schedule of the agent's scripts
├── venv/               Python packages the agent installs with pip
├── state/              whatever it needs to remember between runs
├── claude/             Claude Code's own configuration and sessions
└── logs/               agent.log (one line per run), runs/ (full transcripts)
                        and scripts/ (output of the scheduled scripts)
```

Mounting `/agent/config` read-only is what guarantees the agent can never
rewrite its own rules.

The bible is the system prompt; `CLAUDE.md` is only the agent's notes, which
Claude Code reads as context. When they disagree, the bible wins. A
`guidelines.md` left by an earlier version of the image is moved into
`CLAUDE.md` when the container starts.

### The bible

`bible.md` is free-form Markdown: the agent receives it as is. A structure
that works well is a mission with ordered objectives, the means the agent has,
what it must never do, a table of "if this, then that" cases, and how it
journals its actions, each statement carrying a stable identifier the agent can
cite. [`examples/bible.md`](examples/bible.md) is a complete one to start from.
A container without a bible starts, but skips every run.

## Schedule

Every time the container starts, the agent runs immediately: restarting the
container is the way to ask it to work now. It then runs again every
`AGENT_INTERVAL` seconds, counted from the start of the previous run (86400 by
default, once a day). A run that lasts longer than the interval is followed
immediately by the next one, and two runs never overlap.

The schedule of the agent's own scripts lives in `/agent/data/crontab`. The
agent adds lines there, through `agent-exec` so that the scripts get the
container's environment:

```
*/5 8-20 * * * /usr/local/bin/agent-exec /agent/data/scripts/backup-check
```

The output of each job goes to `/agent/data/logs/scripts/<name>.log`, where
`<name>` is the script's file name; each log keeps its last 10000 lines.
The file is reloaded at the end of every run, and when the container starts.
Every job added or removed is written to `agent.log`. A file that is invalid is
not loaded: the previous jobs stay in place. To change it by hand, edit the file
and restart the container.

## Talking to the agent

Leave a file in `/agent/data/inbox/`, for example `wedding.md`:

```
File the photos of the wedding in a "2024/06 Wedding" album, and tag everyone you can recognise.
```

A new message starts a run within a minute, without waiting for the next
scheduled one. The agent does what the message asks, within its bible, which
a message can never change. It writes its answer at the end of the file and
moves the file to `inbox/done/`, so the conversation stays in one place and in
the inbox's git history.

## Scripts asking the agent

A script stays simple: it does one thing and ends. When it meets a case it
cannot decide alone, it asks the agent and ends anyway:

```bash
/usr/local/bin/agent-ask "The backup of 2023/08 failed 3 times: does case C1 apply?"
```

`agent-ask` returns at once. It starts a run of the agent with the question;
the agent investigates and decides: do nothing, act itself, or run the script
that handles the case. Scripts never wait for an answer, so the flow is
script A, then the agent's decision, then script B.

A question asked while a run is active waits for it to end. A script that the
agent runs while answering may ask again, which makes a chain; `agent.log`
shows each one in full:

```
asked run started, chain backup-check > backup-retry: still failing, give up?
```

A chain longer than `AGENT_ASK_MAX_DEPTH` questions is refused, which is what
stops a loop, and so is any question beyond `AGENT_ASK_MAX_PER_DAY` asked runs
in a day.

## History

`scripts/` and `inbox/` each have their own git repository, created on the
first start. Every run commits what changed in them twice: once before the run
starts, for what changed since the previous run, and once at the end. The
scripts' commit at the end of a run gives its status, its transcript and the
cron jobs it added or removed. The agent is also asked to commit each change to
its scripts itself, citing the rule or case that led to it.

```bash
docker exec agent git -C /agent/data/scripts log --stat
docker exec agent git -C /agent/data/inbox log -p
docker exec agent git -C /agent/data/scripts revert <commit>
```

`crontab` and `CLAUDE.md` are not in either repository; the cron jobs added
and removed are in the scripts' commits and in `agent.log`. The agent runs as
root and can rewrite this history: it shows what happened, it is not a proof.

The first line the container writes to `agent.log` and to its own output gives
the commit of the image it runs and the version of Claude Code.

## Configuration

| Variable                  | Default          | Description                                                        |
| ------------------------- | ---------------- | ------------------------------------------------------------------ |
| `CLAUDE_CODE_OAUTH_TOKEN` | none             | Token of your Claude subscription, created with `claude setup-token`. Required unless `ANTHROPIC_API_KEY` is set. |
| `ANTHROPIC_API_KEY`       | none             | API key, billed per use, instead of the subscription token.        |
| `AGENT_MODEL`             | `sonnet`         | Model used for the runs: an exact model ID, or a Claude Code alias (`haiku`, `sonnet`, `opus`) that follows the newest model of that family. |
| `AGENT_EFFORT`            | `medium`         | Effort level of the runs: `low`, `medium`, `high`, `xhigh` or `max`.        |
| `AGENT_INTERVAL`          | `86400`          | Seconds between the starts of two runs.                            |
| `AGENT_ASK_MAX_DEPTH`     | `256`            | Longest chain of questions from scripts.                           |
| `AGENT_ASK_MAX_PER_DAY`   | `24`             | Maximum number of runs started by questions in a day.              |
| `AGENT_MAX_TURNS`         | `150`            | Maximum number of turns of one run.                                |
| `AGENT_TIMEOUT`           | `2h`             | Maximum duration of one run.                                       |
| `AGENT_KEEP_DAYS`         | `60`             | Days of run transcripts to keep.                                   |
| `TZ`                      | `UTC`            | Time zone of the schedule and of the logs.                         |

Every other variable you set (API keys for the agent's scripts, hosts, tokens
referenced as `${NAME}` in `mcp.json`) is passed to the agent and its scripts.
Variables can also live in `/agent/config/environment`, one `NAME=value` per
line: the file is read at every run and by `agent-exec`, so API keys for the
agent's scripts can stay in the read-only configuration instead of the app
definition.

### MCP servers

`mcp.json` uses Claude Code's format. Declare remote servers with
`"type": "http"`: Claude Code speaks HTTP to them directly, so the `npx
mcp-remote` bridge that Claude Desktop needs is not required, and the image
has no Node.js. See [`examples/mcp.json`](examples/mcp.json). The tokens can be
written directly in the file, which is mounted read-only, or referenced as
`${NAME}` and set as environment variables.


## Run

```bash
docker run -d --name agent \
  -e CLAUDE_CODE_OAUTH_TOKEN=... \
  -e TZ=Europe/Paris \
  -v /srv/agent/config:/agent/config:ro \
  -v /srv/agent/data:/agent/data \
  ghcr.io/adsdworld/container-agent-claude:latest
```

[`examples/truenas.yaml`](examples/truenas.yaml) is the same thing as a TrueNAS
custom app.

```bash
docker logs -f agent
```

shows when each run starts and ends. To start a run by hand:

```bash
docker exec agent agent-run
```

## Security

- The agent runs with `--dangerously-skip-permissions`: inside the container it
  does whatever its bible and its judgment allow, without asking. The container
  is the sandbox, so do not mount anything it must not touch, and never the
  Docker socket.
- It runs as `root` inside the container: it can install system packages and
  change any file of the container. Only `/agent/data` survives a restart, and
  `/agent/config` stays out of its reach as long as it is mounted read-only.
  The image sets `IS_SANDBOX=1`, which Claude Code requires to skip permissions
  as root.
- Files it creates in `/agent/data` belong to root on the host.
- Everything in the environment, including the Claude token, is readable by the
  agent and its scripts.

## License

[Apache-2.0](LICENSE)
