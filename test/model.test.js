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
  relays: {
    total: 3,
    available: 2,
    details: [
      { uri: "stun:stun.netbird.io:443", available: true, error: "" },
      { uri: "rels://relay-1.relay.netbird.io:443", available: true, error: "", transport: "ws" },
      { uri: "turns:turn.netbird.io:443?transport=tcp", available: false, error: "dial timeout" }
    ]
  },
  peers: {
    total: 3,
    connected: 1,
    details: [
      { fqdn: "offline.example.net", netbirdIp: "100.85.1.3", status: "Disconnected" },
      { fqdn: "busy.example.net", netbirdIp: "100.85.1.4", status: "Connecting", connectionType: "-" },
      { fqdn: "nas.example.net", netbirdIp: "100.85.1.2", status: "Connected", connectionType: "P2P", latency: 1500000 }
    ]
  }
}))

assert.strictEqual(parsed.ok, true)
assert.strictEqual(parsed.running, true)
assert.strictEqual(parsed.ip, "100.85.118.182")
assert.strictEqual(Model.formatLatency(1.5), "1.5 ms")
assert.strictEqual(Model.formatLatency(-1), "")

// Peers sort connected → connecting → idle → disconnected.
assert.deepStrictEqual(parsed.peers.map(p => p.name), ["nas", "busy", "offline"])
assert.strictEqual(parsed.peers[0].latencyMs, 1.5)
assert.strictEqual(parsed.peers[0].state, "connected")
assert.strictEqual(parsed.peers[1].state, "connecting")
assert.strictEqual(parsed.peers[1].connecting, true)
assert.strictEqual(parsed.peers[1].connected, false)
assert.strictEqual(parsed.peers[2].state, "disconnected")
assert.strictEqual(parsed.peerConnecting, 1)

assert.strictEqual(Model.peerState("Idle"), "idle")
assert.strictEqual(Model.peerState(""), "disconnected")

// Peer detail fields.
const detailed = Model.normalizePeer({
  fqdn: "nas.example.net",
  netbirdIp: "100.85.1.2/16",
  publicKey: "KEY123",
  status: "Connected",
  connectionType: "Relayed",
  relayAddress: "rels://relay-1.relay.netbird.io:443",
  iceCandidateType: { local: "srflx", remote: "relay" },
  iceCandidateEndpoint: { local: "10.0.0.1:51820", remote: "10.0.0.2:51820" },
  lastWireguardHandshake: "2026-08-15T12:00:00Z",
  transferReceived: 1536, transferSent: 2097152,
  networks: ["10.0.0.5/32"]
})
assert.strictEqual(detailed.key, "nas.example.net")
assert.strictEqual(detailed.publicKey, "KEY123")
assert.strictEqual(detailed.iceLocal, "srflx")
assert.strictEqual(detailed.iceRemote, "relay")
assert.strictEqual(detailed.endpointLocal, "10.0.0.1:51820")
assert.strictEqual(detailed.lastHandshake, "2026-08-15T12:00:00Z")

// A peer that never completed a handshake reports the Go zero time.
const neverShook = Model.normalizePeer({ lastWireguardHandshake: "0001-01-01T00:00:00Z" })
assert.strictEqual(neverShook.lastHandshake, "")
assert.strictEqual(Model.formatRelativeTime(neverShook.lastHandshake), "never")

// Byte and time formatting.
assert.strictEqual(Model.formatBytes(0), "0 B")
assert.strictEqual(Model.formatBytes(512), "512 B")
assert.strictEqual(Model.formatBytes(1536), "1.5 KB")
assert.strictEqual(Model.formatBytes(2097152), "2.0 MB")
assert.strictEqual(Model.formatBytes(1024 * 1024 * 150), "150 MB")

const base = Date.parse("2026-08-15T12:00:00Z")
const ago = (ms) => Model.formatRelativeTime("2026-08-15T12:00:00Z", base + ms)
assert.strictEqual(ago(2000), "just now")
assert.strictEqual(ago(30000), "30 seconds ago")
assert.strictEqual(ago(60000), "1 minute ago")
assert.strictEqual(ago(3600000), "1 hour ago")
assert.strictEqual(ago(90 * 60000), "1 hour ago")
assert.strictEqual(ago(48 * 3600000), "2 days ago")
// Clock skew must not produce "-3 seconds ago".
assert.strictEqual(ago(-5000), "just now")
assert.strictEqual(Model.formatRelativeTime("nonsense"), "")

// The "why is this relayed?" sentence.
assert.strictEqual(Model.candidateLabel("host"), "local network")
assert.strictEqual(Model.candidateLabel("relay"), "TURN relay")
assert.strictEqual(Model.candidateLabel(""), "")
assert.strictEqual(Model.candidatePair(detailed), "STUN reflexive \u2192 TURN relay")
assert.strictEqual(
  Model.connectionSummary(detailed),
  "Relayed via relay-1.relay.netbird.io (STUN reflexive \u2192 TURN relay)")

const direct = Model.normalizePeer({
  fqdn: "a.example.net", status: "Connected", connectionType: "P2P",
  iceCandidateType: { local: "host", remote: "host" }
})
assert.strictEqual(Model.connectionSummary(direct), "Direct peer-to-peer over local network")
assert.strictEqual(Model.connectionSummary(Model.normalizePeer({ status: "Connecting" })), "Negotiating a connection…")
assert.strictEqual(Model.connectionSummary(Model.normalizePeer({ status: "Disconnected" })), "Not connected")
assert.strictEqual(Model.connectionSummary(null), "")

// Search: matches name, IP, connection type and routed networks; multiple
// terms must all match.
assert.strictEqual(Model.matchesPeerQuery(detailed, ""), true)
assert.strictEqual(Model.matchesPeerQuery(detailed, "nas"), true)
assert.strictEqual(Model.matchesPeerQuery(detailed, "NAS"), true)
assert.strictEqual(Model.matchesPeerQuery(detailed, "100.85"), true)
assert.strictEqual(Model.matchesPeerQuery(detailed, "relayed"), true)
assert.strictEqual(Model.matchesPeerQuery(detailed, "10.0.0.5"), true)
assert.strictEqual(Model.matchesPeerQuery(detailed, "nas relayed"), true)
assert.strictEqual(Model.matchesPeerQuery(detailed, "nas p2p"), false)
assert.strictEqual(Model.matchesPeerQuery(detailed, "zzz"), false)

const pool = [detailed, direct, Model.normalizePeer({ fqdn: "off.example.net", status: "Disconnected" })]
assert.strictEqual(Model.filterPeers(pool, "", true).length, 3)
assert.strictEqual(Model.filterPeers(pool, "", false).length, 2)
assert.strictEqual(Model.filterPeers(pool, "off", true).length, 1)
assert.strictEqual(Model.filterPeers(pool, "off", false).length, 0)
assert.strictEqual(Model.filterPeers(null, "x", true).length, 0)

// Relays: unavailable ones sort first so failures are visible without scrolling.
assert.strictEqual(parsed.relayTotal, 3)
assert.strictEqual(parsed.relayAvailable, 2)
assert.strictEqual(parsed.relays[0].name, "turn.netbird.io")
assert.strictEqual(parsed.relays[0].available, false)
assert.strictEqual(parsed.relays[0].error, "dial timeout")
assert.strictEqual(parsed.relays[0].scheme, "turns")
assert.strictEqual(Model.relayName("rels://relay-1.relay.netbird.io:443"), "relay-1.relay.netbird.io")
assert.strictEqual(Model.relayName("stun:stun.netbird.io:5555"), "stun.netbird.io")

// Status output without a relays block must not break older daemons.
const noRelays = Model.parseStatus(JSON.stringify({ daemonStatus: "Connected", management: { connected: true } }))
assert.strictEqual(noRelays.relayTotal, 0)
assert.deepStrictEqual(noRelays.relays, [])

assert.strictEqual(parsed.state, "connected")
assert.strictEqual(parsed.needsLogin, false)
assert.strictEqual(parsed.statusText, "Connected")

// Daemon down.
const down = Model.parseStatus("")
assert.strictEqual(down.ok, false)
assert.strictEqual(down.message, "Disconnected")
assert.strictEqual(Model.parseStatus("not json").ok, false)

// Lifecycle states: every one of these used to collapse into "Disconnected".
for (const [raw, state] of [
  ["Connected", "connected"],
  ["Connecting", "connecting"],
  ["Idle", "idle"],
  ["NeedsLogin", "needsLogin"],
  ["LoginFailed", "loginFailed"],
  ["SessionExpired", "sessionExpired"],
  ["", "unknown"]
]) assert.strictEqual(Model.daemonState(raw), state, raw)

assert.strictEqual(Model.needsLoginState("needsLogin"), true)
assert.strictEqual(Model.needsLoginState("sessionExpired"), true)
assert.strictEqual(Model.needsLoginState("loginFailed"), true)
assert.strictEqual(Model.needsLoginState("idle"), false)
assert.strictEqual(Model.stateLabel("daemonDown"), "Daemon not running")
assert.notStrictEqual(Model.stateHint("needsLogin"), "")
assert.strictEqual(Model.stateHint("connected"), "")

const needsLogin = Model.parseStatus(JSON.stringify({
  daemonStatus: "NeedsLogin",
  management: { connected: false },
  signal: { connected: false },
  peers: { total: 0, connected: 0, details: [] }
}))
assert.strictEqual(needsLogin.ok, true)
assert.strictEqual(needsLogin.running, false)
assert.strictEqual(needsLogin.state, "needsLogin")
assert.strictEqual(needsLogin.needsLogin, true)
assert.strictEqual(needsLogin.statusText, "Login required")
assert.notStrictEqual(needsLogin.hint, "")

// A daemon reporting Connecting must not read as connected just because
// management is up.
const connectingDaemon = Model.parseStatus(JSON.stringify({
  daemonStatus: "Connecting",
  management: { connected: true },
  peers: { total: 0, connected: 0, details: [] }
}))
assert.strictEqual(connectingDaemon.state, "connecting")
assert.strictEqual(connectingDaemon.connecting, true)
assert.strictEqual(connectingDaemon.running, false)

// Daemons too old to report daemonStatus fall back to the management link.
const legacy = Model.parseStatus(JSON.stringify({
  management: { connected: true },
  peers: { total: 0, connected: 0, details: [] }
}))
assert.strictEqual(legacy.state, "connected")
assert.strictEqual(legacy.running, true)

// An unreachable daemon: `timeout` kills the call (124), or the CLI prints
// its gRPC dial error while retrying.
assert.strictEqual(Model.daemonUnreachable(124, ""), true)
assert.strictEqual(Model.daemonUnreachable(137, ""), true)
assert.strictEqual(Model.daemonUnreachable(1, 'dial unix /var/run/netbird.sock: connect: no such file or directory'), true)
assert.strictEqual(Model.daemonUnreachable(1, "failed to connect to daemon error"), true)
assert.strictEqual(Model.daemonUnreachable(1, "some other failure"), false)
assert.strictEqual(Model.daemonUnreachable(0, ""), false)

// SSO prompt parsing, in both the browser and --no-browser wordings.
const prompt = Model.parseLoginPrompt(
  "Please do the SSO login in your browser. \n" +
  "If your browser didn't open automatically, use this URL to log in:\n\n" +
  "https://login.example.com/activate?user_code=ABCD-EFGH and enter the code ABCD-EFGH to authenticate.")
assert.strictEqual(prompt.url, "https://login.example.com/activate?user_code=ABCD-EFGH")
assert.strictEqual(prompt.code, "ABCD-EFGH")

const noCode = Model.parseLoginPrompt("Use this URL to log in:\n\nhttps://login.example.com/device ")
assert.strictEqual(noCode.url, "https://login.example.com/device")
assert.strictEqual(noCode.code, "")
assert.deepStrictEqual(Model.parseLoginPrompt("Connecting to management..."), { url: "", code: "" })

assert.strictEqual(Model.versionMismatch("0.77.0", "0.76.3"), true)
assert.strictEqual(Model.versionMismatch("0.77.0", "0.77.0"), false)
assert.strictEqual(Model.versionMismatch("", "0.77.0"), false)
assert.strictEqual(parsed.versionMismatch, false)

// `netbird networks list` is text-only; parse both resource shapes.
const networks = Model.parseNetworks([
  "Available Networks:",
  "",
  "  - ID: Proxy",
  "    Network: 10.0.0.172/32",
  "    Status: Selected",
  "",
  "  - ID: Office",
  "    Domains: example.com, www.example.com",
  "    Status: Not Selected",
  "    Resolved IPs:",
  "      [example.com]: 93.184.216.34, 93.184.216.35",
  "",
  "  - ID: Lab",
  "    Domains: lab.example.com",
  "    Status: Selected",
  "    Resolved IPs: -",
  ""
].join("\n"))

assert.strictEqual(networks.ok, true)
assert.strictEqual(networks.networks.length, 3)
assert.strictEqual(networks.networks[0].id, "Proxy")
assert.strictEqual(networks.networks[0].range, "10.0.0.172/32")
assert.strictEqual(networks.networks[0].selected, true)
assert.deepStrictEqual(networks.networks[1].domains, ["example.com", "www.example.com"])
assert.strictEqual(networks.networks[1].selected, false)
assert.strictEqual(networks.networks[1].resolvedIps[0].domain, "example.com")
assert.deepStrictEqual(networks.networks[1].resolvedIps[0].ips, ["93.184.216.34", "93.184.216.35"])
assert.deepStrictEqual(networks.networks[2].resolvedIps, [])
assert.strictEqual(Model.selectedNetworkCount(networks.networks), 2)
assert.strictEqual(Model.networkSubtitle(networks.networks[0]), "10.0.0.172/32")
assert.strictEqual(Model.networkSubtitle(networks.networks[1]), "example.com, www.example.com")

assert.deepStrictEqual(Model.parseNetworks("No networks available.").networks, [])
assert.deepStrictEqual(Model.parseNetworks("").networks, [])
assert.strictEqual(Model.parseNetworks("Error: failed to list network: rpc error").ok, false)

console.log("Model tests passed")
