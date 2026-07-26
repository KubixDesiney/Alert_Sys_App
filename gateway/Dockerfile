# SIAS reference edge gateway — minimal, non-root container.
# Build:  docker build -t sias-gateway gateway/
# Run:    docker run -d --restart unless-stopped \
#           -v /opt/sias/gateway.config.json:/app/gateway.config.json:ro \
#           -v sias-gateway-queue:/app/queue \
#           sias-gateway
# Protocol libraries are optional peers — bake in only what your plant uses:
#   docker build --build-arg PROTOCOL_DEPS="mqtt sparkplug-payload" -t sias-gateway gateway/
FROM node:20-slim

ARG PROTOCOL_DEPS=""

WORKDIR /app
COPY package.json ./
COPY bin ./bin
COPY src ./src

# Core has zero required deps; install only the requested protocol peers.
RUN if [ -n "$PROTOCOL_DEPS" ]; then npm install --omit=dev $PROTOCOL_DEPS; fi \
  && mkdir -p /app/queue \
  && chown -R node:node /app

USER node
VOLUME ["/app/queue"]

ENTRYPOINT ["node", "bin/sias-gateway.mjs"]
CMD ["--config", "gateway.config.json"]
