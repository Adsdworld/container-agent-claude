FROM debian:trixie-slim

ARG CLAUDE_VERSION=stable

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        ca-certificates curl wget jq git unzip sqlite3 \
        cron tini tzdata procps util-linux less nano \
        python3 python3-pip python3-venv python3-requests python3-yaml \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://claude.ai/install.sh | bash -s "${CLAUDE_VERSION}"

ENV PATH=/agent/data/venv/bin:/root/.local/bin:$PATH \
    CLAUDE_CONFIG_DIR=/agent/data/claude \
    IS_SANDBOX=1 \
    DISABLE_AUTOUPDATER=1 \
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 \
    AGENT_MODEL=sonnet \
    AGENT_EFFORT=medium

COPY rootfs/ /
RUN chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/agent-run /usr/local/bin/agent-exec /usr/local/bin/agent-scheduler /usr/local/bin/agent-ask \
 && git config --system --add safe.directory '*'

ARG IMAGE_VERSION=dev
ENV AGENT_IMAGE_VERSION=$IMAGE_VERSION

VOLUME ["/agent/config", "/agent/data"]
WORKDIR /agent/data
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
