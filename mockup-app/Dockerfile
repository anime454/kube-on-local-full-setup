FROM golang:1.26-alpine AS builder

RUN apk add --no-cache ca-certificates git

ENV GOTOOLCHAIN=auto

WORKDIR /app

COPY go.mod ./
COPY go.sum* ./
# Try to pre-download deps when go.sum exists (better layer caching).
# If go.sum is absent, skip — we'll resolve after sources are copied.
RUN if [ -f go.sum ]; then go mod download; fi

COPY . .

# Ensure go.sum is complete & consistent with sources, then build.
RUN go mod tidy

RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o mockup-app main.go

# Final stage
FROM alpine:3.18

RUN apk --no-cache add \
    ca-certificates \
    tzdata \
    wget

RUN adduser -D -u 1001 -s /bin/sh appuser

WORKDIR /app

COPY --from=builder /app/mockup-app .

RUN chown -R appuser:appuser /app

USER appuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/ || exit 1

ENV GO_ENV=production \
    LOG_LEVEL=info \
    SERVER_PORT=3000

CMD ["./mockup-app"]
