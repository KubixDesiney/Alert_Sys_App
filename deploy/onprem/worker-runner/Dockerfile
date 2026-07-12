# Build context = repo root (see docker-compose.yml) so we can vendor the shared
# scoring. Build:  docker compose build worker-runner
FROM node:20-alpine
WORKDIR /app/worker-runner
COPY deploy/onprem/worker-runner/package.json ./
RUN npm install --omit=dev || true
COPY deploy/onprem/worker-runner/ ./
# Licence library lives beside the runner (imported as ../license/…).
COPY deploy/onprem/license/ /app/license/
# Vendor the cloud worker's pure scoring so on-prem assigns identically.
COPY cloudflare_worker.js ./vendor/cloudflare_worker.js
COPY worker ./vendor/worker
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD wget -qO- http://127.0.0.1:8787/health >/dev/null || exit 1
CMD ["node", "index.mjs"]
