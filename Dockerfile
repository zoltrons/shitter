FROM nimlang/nim:2.2.6-alpine-regular AS nim

# Disable link-time optimization by default (faster build)
ARG ENABLE_LTO=0

# Platform-aware cache mounts for multi-arch builds
ARG TARGETPLATFORM

RUN --mount=type=cache,id=apk-${TARGETPLATFORM},target=/var/cache/apk,sharing=locked \
    apk add libsass-dev pcre

WORKDIR /src/nitter

COPY nitter.nimble .
RUN --mount=type=cache,id=nimble-${TARGETPLATFORM},target=/root/.nimble,sharing=locked \
    --mount=type=cache,id=nim-${TARGETPLATFORM},target=/root/.cache/nim,sharing=locked \
    nimble install -y --depsOnly

COPY . .
RUN --mount=type=cache,id=nimble-${TARGETPLATFORM},target=/root/.nimble,sharing=locked \
    --mount=type=cache,id=nim-${TARGETPLATFORM}-lto-${ENABLE_LTO},target=/root/.cache/nim,sharing=locked \
    sh -c 'set -e; \
      LTO=""; \
      if [ "$ENABLE_LTO" = "1" ]; then LTO="-d:lto"; fi; \
      nimble build -d:danger -d:strip --mm:refc $LTO; \
      nimble scss; \
      nimble md'

FROM alpine:latest
WORKDIR /src/
RUN apk --no-cache add pcre ca-certificates openssl
COPY --from=nim /src/nitter/nitter ./
COPY --from=nim /src/nitter/nitter.example.conf ./nitter.conf
COPY --from=nim /src/nitter/public ./public
EXPOSE 8080
RUN adduser -h /src/ -D -s /bin/sh nitter
USER nitter
CMD ./nitter
