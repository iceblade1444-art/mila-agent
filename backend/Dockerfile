FROM node:24-slim

WORKDIR /app

COPY package.json ./
COPY package-lock.json ./
RUN npm ci --omit=dev

COPY db.mjs server.mjs ./

ENV PORT=8787
EXPOSE 8787

CMD ["node", "server.mjs"]
