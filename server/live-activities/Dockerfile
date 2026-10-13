FROM node:24.15.0-bookworm-slim
WORKDIR /app
COPY package.json ./
COPY src ./src
RUN mkdir /data && chown node:node /data
USER node
ENV PORT=8080 DATABASE_PATH=/data/live-activities.sqlite
EXPOSE 8080
CMD ["node", "src/main.mjs"]
