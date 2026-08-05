#!/bin/sh
# Fix /data ownership when a host directory is mounted over it
chown -R codexa:codexa /data
exec setpriv --reuid=codexa --regid=codexa --init-groups node server/index.js
