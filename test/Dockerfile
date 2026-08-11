# Test harness for the johnny-decimal-zettelkasten template.
#
# Provides an isolated environment with every dependency the setup scripts
# check for, so the migration can be exercised end-to-end without touching the
# host's HOME, plugin registrations, or vault config.

FROM node:22-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      git-lfs \
      jq \
      sqlite3 \
      shellcheck \
      python3-yaml \
      ca-certificates \
      curl \
    && rm -rf /var/lib/apt/lists/*

# Non-root user with its own HOME, so ~/.obsidian-mcp.config.json and any
# plugin state stay inside the container.
RUN useradd -m -s /bin/bash tester
USER tester
WORKDIR /work

# Warm the npx cache at build time so test runs do not re-download the server.
RUN npx -y @jabez007/obsidian-vault-mcp@2 --help >/dev/null 2>&1 || true

ENV REPO_SRC=/repo \
    WORK_DIR=/work/repo

CMD ["bash", "/repo/test/run-tests.sh"]
