FROM golang:1.24-alpine AS build
WORKDIR /src
COPY crossplatform/go.mod crossplatform/go.sum* ./
RUN go mod download
COPY crossplatform/ ./
RUN CGO_ENABLED=0 go build -o /out/bilicastd ./cmd/bilicastd

FROM alpine:3.21
RUN apk add --no-cache ca-certificates ffmpeg
COPY --from=build /out/bilicastd /usr/local/bin/bilicastd
ENV BILICAST_CONTROL_ADDR=0.0.0.0:18787 \
    BILICAST_PROXY_ADDR=0.0.0.0:18788 \
    BILICAST_CONFIG=/data/config.json
VOLUME ["/data"]
EXPOSE 18787 18788
ENTRYPOINT ["/usr/local/bin/bilicastd"]
