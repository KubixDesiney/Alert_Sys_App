# Build context = repo root (see docker-compose.yml).
FROM node:20-alpine
WORKDIR /app/edge-gateway
COPY deploy/onprem/edge-gateway/package.json ./
# Optional protocol deps (mqtt, node-opcua) are best-effort: HTTP adapters
# work with zero dependencies; air-gapped sites vendor these from an internal
# registry when the Industrial plan needs them.
RUN npm install --omit=dev || npm install --omit=dev --omit=optional || true
COPY deploy/onprem/edge-gateway/ ./
# Shared modules imported as ../worker-runner/…
COPY deploy/onprem/worker-runner/logger.mjs /app/worker-runner/logger.mjs
COPY deploy/onprem/worker-runner/retry.mjs /app/worker-runner/retry.mjs
EXPOSE 8788
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD wget -qO- http://127.0.0.1:8788/health >/dev/null || exit 1
CMD ["node", "index.mjs"]
