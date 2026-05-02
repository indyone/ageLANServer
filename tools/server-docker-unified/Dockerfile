# syntax=docker/dockerfile:1

# Build both genCert and server binaries in a single compiler stage
FROM golang:1.26-alpine3.23 AS compiler
WORKDIR /app
COPY tools/server-docker-unified/go.work.template go.work
COPY common common
COPY server server
COPY server-genCert server-genCert
RUN mkdir build
RUN cp -r server/resources build/resources \
    && rm -rf build/resources/windows \
    && rm -rf build/resources/unix \
    && cp -r server/resources/config build/config.defaults
RUN mkdir -p build/resources/certificates
RUN go build -ldflags="-s -w" -o build/bin/genCert ./server-genCert
RUN go build -ldflags="-s -w" -o build/server ./server

# Compress both binaries
FROM alpine:3.23 AS compressor
RUN apk add --no-cache upx
WORKDIR /app
COPY --from=compiler /app/build/bin/genCert bin/genCert
COPY --from=compiler /app/build/server server
RUN upx --lzma bin/genCert server

# Runtime image — alpine (not scratch) so the entrypoint shell script can run
FROM alpine:3.23
EXPOSE 443
WORKDIR /app
COPY --from=compiler /app/build/resources resources
# Pristine game configs for entrypoint seeding — kept outside the config volume
# so bind mounts (which hide image content) don't affect them.
COPY --from=compiler /app/build/config.defaults resources/config.defaults
COPY --from=compressor /app/bin bin
COPY --from=compressor /app/server server
COPY tools/server-docker-unified/entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh
VOLUME /app/resources/config
VOLUME /app/resources/certificates
VOLUME /app/logs
ENTRYPOINT ["./entrypoint.sh"]
