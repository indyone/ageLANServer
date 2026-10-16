# syntax=docker/dockerfile:1

# Targets:
#   server       (default) genCert + server, small image.
#   battleserver server plus Wine and battle-server-manager, so the game's
#                Windows BattleServer.exe can run in the same container.

# Build genCert, server and battle-server-manager in a single compiler stage
FROM golang:1.26-alpine3.24 AS compiler
WORKDIR /app
COPY tools/server-docker-unified/go.work.template go.work
COPY common common
COPY battle-server-broadcast battle-server-broadcast
COPY server server
COPY server-genCert server-genCert
COPY battle-server-manager battle-server-manager
RUN mkdir build
RUN cp -r server/resources build/resources \
    && rm -rf build/resources/windows \
    && rm -rf build/resources/unix \
    && cp -r server/resources/config build/config.defaults
RUN mkdir -p build/resources/certificates
RUN go build -ldflags="-s -w" -o build/bin/genCert ./server-genCert
RUN go build -ldflags="-s -w" -o build/bin/battle-server-manager ./battle-server-manager
RUN go build -ldflags="-s -w" -o build/server ./server

# Compress the binaries
FROM alpine:3.24 AS compressor
RUN apk add --no-cache upx
WORKDIR /app
COPY --from=compiler /app/build/bin/genCert bin/genCert
COPY --from=compiler /app/build/bin/battle-server-manager bin/battle-server-manager
COPY --from=compiler /app/build/server server
RUN upx --lzma bin/genCert bin/battle-server-manager server

# Runtime image — alpine (not scratch) so the entrypoint shell script can run
FROM alpine:3.24 AS server
LABEL org.opencontainers.image.source="https://github.com/indyone/ageLANServer"
EXPOSE 443
WORKDIR /app
COPY --from=compiler /app/build/resources resources
# Pristine game configs for entrypoint seeding — kept outside the config volume
# so bind mounts (which hide image content) don't affect them.
COPY --from=compiler /app/build/config.defaults resources/config.defaults
COPY --from=compressor /app/bin/genCert bin/genCert
COPY --from=compressor /app/server server
COPY tools/server-docker-unified/entrypoint.sh entrypoint.sh
RUN chmod +x entrypoint.sh
VOLUME /app/resources/config
VOLUME /app/resources/certificates
VOLUME /app/logs
ENTRYPOINT ["./entrypoint.sh"]

# Same image plus a minimal Wine and the manager that starts BattleServer.exe.
FROM server AS battleserver
RUN apk add --no-cache wine \
 && WINEPREFIX=/wine WINEARCH=win64 WINEDEBUG=-all DISPLAY="" \
    wineboot --init 2>/dev/null || true \
 && rm -rf /wine/drive_c/windows/syswow64 \
           /wine/drive_c/windows/twain_32 \
           /wine/drive_c/windows/system32/gecko \
           /wine/drive_c/windows/Microsoft.NET \
           /wine/drive_c/windows/explorer.exe \
           /wine/drive_c/windows/winhlp32.exe \
           /wine/drive_c/windows/winsxs
ENV WINEPREFIX=/wine \
    WINEDEBUG=-all \
    WINEARCH=win64 \
    DISPLAY="" \
    AGELANSERVER_BATTLE_SERVER_MANAGER_Ports_Bs=27012 \
    AGELANSERVER_BATTLE_SERVER_MANAGER_Ports_WebSocket=27112 \
    AGELANSERVER_BATTLE_SERVER_MANAGER_Ports_OutOfBand=27212 \
    AGELANSERVER_BATTLE_SERVER_MANAGER_CertsPath=/app/resources/certificates \
    AGELANSERVER_BATTLE_SERVER_MANAGER_Executable_Path=/opt/battleserver/BattleServer.exe
COPY --from=compressor /app/bin/battle-server-manager bin/battle-server-manager

# Keep the small image as the default when no --target is given.
FROM server
