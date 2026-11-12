# Pinned runtime for the isolated Claude Code runner.
FROM node:22.14.0-alpine3.21

ARG CLAUDE_CODE_VERSION=2.1.319
RUN npm install --global "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    && addgroup -S -g 10001 claude \
    && adduser -S -D -u 10001 -G claude claude \
    && mkdir -p /workspace /home/claude \
    && chown -R claude:claude /workspace /home/claude

USER claude
WORKDIR /workspace
ENV HOME=/home/claude
ENTRYPOINT ["claude"]
