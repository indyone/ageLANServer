#!/bin/sh
set -e

# Seed game-specific config files into the config volume if they are missing.
# Bind-mount volumes replace image content at runtime, hiding the files baked
# into the image. We restore them from the baked-in defaults so the server can
# always find its per-game resources (login.json, etc.).
for game in age1 age2 age3 age4 athens; do
    if [ ! -d "resources/config/$game" ]; then
        echo "Seeding config for $game..."
        cp -r "resources/config.defaults/$game" "resources/config/"
    fi
done

# Seed a commented example config.toml so the user can easily customise it.
# Rename to config.toml to activate it.
if [ ! -f "resources/config/config.toml.example" ]; then
    echo "Seeding config.toml.example..."
    cp "resources/config.defaults/config.toml" "resources/config/config.toml.example"
fi

# Generate SSL certificates on first run only. Checking for the files avoids
# depending on genCert's "already exists" exit code, which shifts between
# upstream versions.
if [ ! -f resources/certificates/cert.pem ] || [ ! -f resources/certificates/key.pem ]; then
    CERT_EXIT=0
    ./bin/genCert || CERT_EXIT=$?
    if [ "$CERT_EXIT" -ne 0 ]; then
        echo "Certificate generation failed (exit code: $CERT_EXIT)" >&2
        exit "$CERT_EXIT"
    fi
fi

# GAMES must be set to exactly one game (e.g. age1, age2, age3, age4, athens).
# Run a separate container per game when you want multiple titles.
if [ -z "$GAMES" ]; then
    echo "Error: the GAMES environment variable must be set to one game (e.g. GAMES=age2)." >&2
    exit 1
fi

# Start the game's own BattleServer.exe (under Wine) when one is mounted.
# Only the agelanserver-battleserver image ships Wine and the manager.
# The manager records it where the server reads it, so it must run first.
BS_EXE=/app/battleserver/BattleServer.exe
BS_RUN_DIR=/opt/battleserver
BS_IMAGE=ghcr.io/indyone/agelanserver-battleserver
if [ -f "$BS_EXE" ] && [ -x ./bin/battle-server-manager ]; then
    echo "Starting BattleServer for $GAMES..."
    # Run a local copy: Wine cannot reliably map executables from bind mounts
    # (Windows hosts, Unraid user shares) and crashes at startup.
    mkdir -p "$BS_RUN_DIR"
    cp "$BS_EXE" "$BS_RUN_DIR/BattleServer.exe"
    ./bin/battle-server-manager clean || true
    BS_LOG="/app/logs/battle-server-manager/$GAMES/$(date +%Y-%m-%dT%H-%M-%S)"
    if ! ./bin/battle-server-manager start --hideWindow -e "$GAMES" --logRoot="$BS_LOG"; then
        echo "BattleServer failed to start (see $BS_LOG)." >&2
        exit 1
    fi
    # If BattleServer dies, stop the container so its restart policy recovers it.
    (
        while pgrep -f BattleServer.exe > /dev/null; do sleep 10; done
        echo "BattleServer.exe stopped, stopping the container." >&2
        kill -TERM 1
    ) &
elif [ "$GAMES" = "age4" ] || [ "$GAMES" = "athens" ]; then
    echo "Error: $GAMES requires a BattleServer. Use the $BS_IMAGE image and mount a folder containing BattleServer.exe at /app/battleserver." >&2
    exit 1
elif [ -f "$BS_EXE" ]; then
    echo "Warning: BattleServer.exe is mounted but this image cannot run it. Use the $BS_IMAGE image instead." >&2
else
    echo "No BattleServer in use: host with 'Use Local Lan Server' in the game's Server list."
fi

exec ./server --games "$GAMES" --announce true "$@"
