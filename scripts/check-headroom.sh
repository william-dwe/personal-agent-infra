#!/usr/bin/env bash
# Read-only smoke test: no provider request or billable generation.
set -euo pipefail
[ -z "$(docker port headroom)" ] || { echo 'Headroom must not publish host ports' >&2; exit 1; }
! tailscale serve status | grep -qE ':8787([[:space:]]|$)' || { echo 'Remove the Headroom Tailscale forwarding rule' >&2; exit 1; }
docker exec -i 9router node --input-type=module <<'JS'
import assert from 'node:assert/strict';
const base = 'http://headroom:8787';
const health = await fetch(`${base}/health`);
assert.equal(health.status, 200);
const response = await fetch(`${base}/v1/compress`, {
  method: 'POST', headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({model: 'gpt-4o', messages: [{role: 'user', content: 'Hello'}]}),
});
const body = await response.json();
assert.equal(response.status, 200, JSON.stringify(body));
assert.ok(Array.isArray(body.messages), 'Expected compressed messages');
console.log('PASS: 9router reaches health and /v1/compress without a token; no host/tailnet port.');
JS
