const assert = require("assert")
const Model = require("../Model.js")

assert.strictEqual(Model.stripCidr("100.85.1.2/16"), "100.85.1.2")
assert.strictEqual(Model.hostname("laptop.example.net", "100.1.2.3"), "laptop")

const parsed = Model.parseStatus(JSON.stringify({
  daemonStatus: "Connected",
  management: { connected: true },
  signal: { connected: true },
  netbirdIp: "100.85.118.182/16",
  fqdn: "desktop.example.net",
  profileName: "default",
  peers: {
    total: 2,
    connected: 1,
    details: [
      { fqdn: "offline.example.net", netbirdIp: "100.85.1.3", status: "Disconnected" },
      { fqdn: "nas.example.net", netbirdIp: "100.85.1.2", status: "Connected", connectionType: "P2P", latency: 1500000 }
    ]
  }
}))

assert.strictEqual(parsed.ok, true)
assert.strictEqual(parsed.running, true)
assert.strictEqual(parsed.ip, "100.85.118.182")
assert.strictEqual(parsed.peers[0].name, "nas")
assert.strictEqual(parsed.peers[0].latencyMs, 1.5)
assert.strictEqual(Model.formatLatency(1.5), "1.5 ms")
assert.strictEqual(Model.formatLatency(-1), "")

console.log("Model tests passed")
