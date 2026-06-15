FROM node:20-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev || true
COPY . .
EXPOSE 8787
CMD ["node", "index.mjs"]
