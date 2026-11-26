# Build from the repository root: docker build -f docker/Dockerfile -t channelforge .
FROM node:22-bookworm-slim AS gui
WORKDIR /build/gui
COPY gui/package.json gui/package-lock.json ./
RUN npm ci
COPY gui/ ./
COPY schemas/ /build/schemas/
RUN npm run build

FROM mcr.microsoft.com/powershell:7.6.4-debian-bookworm-slim
RUN useradd --system --uid 10001 --home-dir /app channelforge \
 && mkdir -p /app /data \
 && chown channelforge /data
WORKDIR /app
COPY src/ ./src/
COPY scripts/ ./scripts/
COPY schemas/ ./schemas/
COPY config/ ./config/
COPY VERSION ./VERSION
COPY docker/entrypoint.ps1 ./docker/entrypoint.ps1
COPY --from=gui /build/gui/dist ./gui/dist
USER channelforge
VOLUME /data
EXPOSE 47850
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["pwsh", "-NoProfile", "-Command", "try { exit ([int]((Invoke-WebRequest -Uri http://127.0.0.1:47850/health -UseBasicParsing).StatusCode -ne 200)) } catch { exit 1 }"]
ENTRYPOINT ["pwsh", "-NoProfile", "-File", "/app/docker/entrypoint.ps1"]
