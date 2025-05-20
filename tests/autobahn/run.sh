#!/bin/sh

set -e

jai-linux tests/autobahn/server.jai

tests/autobahn/server &

docker run -it --rm \
    -v "${PWD}/tests/autobahn/config:/config" \
    -v "${PWD}/tests/autobahn/reports:/reports" \
    --network="host" \
    crossbario/autobahn-testsuite \
    wstest -m fuzzingclient -s config/fuzzingclient.json

PID=$(pgrep -f tests/autobahn/server)

if [ -n "$PID" ]; then
    kill -9 "$PID"
fi
