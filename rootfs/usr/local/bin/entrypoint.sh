#!/bin/bash
set -euo pipefail

CONFIG=/agent/config
DATA=/agent/data
ENV_FILE=/run/agent.env
SCHEDULE="$DATA/crontab"
LOG="$DATA/logs/agent.log"

mkdir -p "$DATA/scripts" "$DATA/inbox/done" "$DATA/state" "$DATA/logs/runs" "$DATA/claude"
touch "$LOG"

if [ ! -x "$DATA/venv/bin/python" ]; then
    python3 -m venv --system-site-packages "$DATA/venv"
fi

install -m 600 /dev/null "$ENV_FILE"
for name in $(compgen -e); do
    case "$name" in
        HOME | PWD | OLDPWD | SHLVL | _ | HOSTNAME | TERM) continue ;;
    esac
    printf 'export %s=%q\n' "$name" "${!name}" >> "$ENV_FILE"
done

if [ ! -e "$SCHEDULE" ]; then
    echo '# Jobs of the agent, called through /usr/local/bin/agent-exec' > "$SCHEDULE"
fi
# Runs of the agent are no longer scheduled by cron: drop the old line.
sed -i '\|/usr/local/bin/agent-run|d' "$SCHEDULE"
crontab "$SCHEDULE" || echo "$(date -Is) warning: $SCHEDULE is invalid, no job scheduled" >> "$LOG"

# guidelines.md, appended to the system prompt before, became CLAUDE.md.
if [ -s "$DATA/guidelines.md" ]; then
    cat "$DATA/guidelines.md" >> "$DATA/CLAUDE.md"
    rm "$DATA/guidelines.md"
fi

# Each of these folders has its own git history.
for repository in scripts inbox; do
    if [ ! -d "$DATA/$repository/.git" ]; then
        git init -q -b main "$DATA/$repository"
        git -C "$DATA/$repository" config user.name agent
        git -C "$DATA/$repository" config user.email agent@localhost
    fi
done
[ -e "$DATA/scripts/.gitignore" ] || printf '%s\n' __pycache__/ '*.pyc' > "$DATA/scripts/.gitignore"

echo "$(date -Is) container started, image ${AGENT_IMAGE_VERSION:-unknown}, $(claude --version 2>/dev/null | head -1)" | tee -a "$LOG"
echo "$(date -Is) a run every ${AGENT_INTERVAL:-86400} s" >> "$LOG"
[ -s "$CONFIG/bible.md" ] || echo "$(date -Is) warning: $CONFIG/bible.md is missing or empty, runs will be skipped" >> "$LOG"

/usr/local/bin/agent-scheduler &

tail -n 0 -F "$LOG" &
exec cron -f
