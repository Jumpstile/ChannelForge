# Build from the repository root: docker build -f docker/Dockerfile -t channelforge .
FROM node:22-bookworm-slim AS gui
WORKDIR /build/gui
COPY gui/package.json gui/package-lock.json ./
RUN npm ci
COPY gui/ ./
COPY schemas/ /build/schemas/
RUN npm run build

# Microsoft's ready-made PowerShell image does not offer PowerShell 7.6 yet, so
# download the official release and check its published SHA-256 before using it.
FROM ubuntu:24.04 AS pwsh
ARG PWSH_VERSION=7.6.7
ARG PWSH_SHA256=6896F9E3A6B0A354BF470835A96DA76D2F801CD50DCF047AD7C4563BF93BF431
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && curl -fsSL -o /tmp/pwsh.tar.gz "https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-x64.tar.gz" \
 && echo "$(echo ${PWSH_SHA256} | tr 'A-F' 'a-f')  /tmp/pwsh.tar.gz" | sha256sum -c - \
 && mkdir -p /opt/microsoft/powershell/7 \
 && tar -xzf /tmp/pwsh.tar.gz -C /opt/microsoft/powershell/7 \
 && chmod +x /opt/microsoft/powershell/7/pwsh

FROM ubuntu:24.04
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libicu74 libssl3t64 \
 && rm -rf /var/lib/apt/lists/*
COPY --from=pwsh /opt/microsoft/powershell/7 /opt/microsoft/powershell/7
RUN ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh \
 && useradd --system --uid 10001 --home-dir /app channelforge \
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
