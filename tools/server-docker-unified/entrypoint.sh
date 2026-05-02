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

# Generate SSL certificates on first run.
# genCert exits 0 when newly generated, 8 (ErrCertCreateExisting) when they
# already exist, and any other non-zero code on a real error.
CERT_EXIT=0
./bin/genCert || CERT_EXIT=$?
if [ "$CERT_EXIT" -ne 0 ] && [ "$CERT_EXIT" -ne 8 ]; then
    echo "Certificate generation failed (exit code: $CERT_EXIT)" >&2
    exit "$CERT_EXIT"
fi

# GAMES must be set to exactly one game (e.g. age1, age2, age3, age4, athens).
# Run a separate container per game when you want multiple titles.
if [ -z "$GAMES" ]; then
    echo "Error: the GAMES environment variable must be set to one game (e.g. GAMES=age2)." >&2
    exit 1
fi

exec ./server --games "$GAMES" --announce true "$@"
