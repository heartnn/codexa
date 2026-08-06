# ── Build stage ───────────────────────────────────────────────────────────────
# Installs all deps (including devDeps for esbuild), transpiles public/ → dist/
# for Chrome 69 / older Android WebView, then prunes devDeps before handoff.
#
# Debian-based (not -alpine): kept since it's already proven stable, but the actual root
# cause of the native crash ("Assertion failed: (env) != nullptr" in
# node::RemoveEnvironmentCleanupHook, thrown from better-sqlite3's Statement destructor) was
# better-sqlite3@11.x predating Node 24 support: it had no prebuilt binary for Node 24's ABI,
# so npm fell back to compiling from source against a version never actually tested against
# Node 24, producing a subtly broken binary that crashed intermittently (on startup, or later
# on the first real query, depending on timing). Fixed by bumping better-sqlite3 to ^13.x
# (package.json), which ships real prebuilt N-API binaries for Node 24 for both glibc and
# musl, so no native compilation happens for it anymore either way.
FROM node:24-bookworm-slim AS build

WORKDIR /app

# python3/make/g++ are required to compile the native bcrypt addon
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build
RUN npm prune --omit=dev

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM node:24-bookworm-slim

WORKDIR /app

# Non-root user for security. setpriv (util-linux, present by default) is the Debian
# equivalent of Alpine's su-exec: it execve()s straight into the target command instead of
# forking, so node still ends up as PID 1 and receives Docker's signals directly.
RUN groupadd -r codexa && useradd -r -g codexa codexa \
    && apt-get update && apt-get install -y --no-install-recommends util-linux \
    && rm -rf /var/lib/apt/lists/*

# Production node_modules (devDeps already pruned) + transpiled dist/
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
# Source files (public/ kept as server-side fallback; dist/ wins at runtime)
COPY . .

# Data directory — mount a named volume here for persistence
RUN mkdir -p /data && chown codexa:codexa /data && \
    chmod +x /app/entrypoint.sh
ENV DATA_DIR=/data

EXPOSE 3000

# wget/curl aren't in the slim base — use Node's own (stable since Node 18) fetch instead.
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/manifest.json').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

ENTRYPOINT ["/app/entrypoint.sh"]
