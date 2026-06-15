# Build context = repo root (see docker-compose.yml) so we can vendor the shared
# scoring. Build:  docker compose build worker-runner
FROM node:20-alpine
WORKDIR /app
COPY deploy/onprem/worker-runner/package.json ./
RUN npm install --omit=dev || true
COPY deploy/onprem/worker-runner/ ./
# Vendor the cloud worker's pure scoring so on-prem assigns identically.
COPY cloudflare_worker.js ./vendor/cloudflare_worker.js
COPY worker ./vendor/worker
EXPOSE 8787
CMD ["node", "index.mjs"]
