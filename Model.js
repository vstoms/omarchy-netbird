function stripCidr(value) {
  return String(value || "").split("/")[0]
}

function hostname(fqdn, fallback) {
  var name = String(fqdn || "")
  if (name !== "") return name.split(".")[0] || name
  return stripCidr(fallback) || "Unknown"
}

function connectedStatus(status) {
  return String(status || "").toLowerCase() === "connected"
}

// NetBird reports per-peer status as Connected / Connecting / Idle /
// Disconnected. Collapsing everything that is not "Connected" into "down"
// hides the most interesting case: a peer that is mid-handshake right now.
function peerState(status) {
  var value = String(status || "").toLowerCase()
  if (value === "connected") return "connected"
  if (value === "connecting") return "connecting"
  if (value === "idle") return "idle"
  return "disconnected"
}

// WireGuard reports "no handshake yet" as the Go zero time.
function isZeroTime(value) {
  var text = String(value || "")
  return text === "" || text.indexOf("0001-01-01") === 0
}

function normalizePeer(peer) {
  var value = peer || {}
  var latencyNs = Number(value.latency || 0)
  var state = peerState(value.status)
  var ice = value.iceCandidateType || {}
  var endpoint = value.iceCandidateEndpoint || {}
  var fqdn = String(value.fqdn || "")
  var ip = stripCidr(value.netbirdIp)
  return {
    fqdn: fqdn,
    name: hostname(value.fqdn, value.netbirdIp),
    ip: ip,
    // Stable identity for "which row is expanded", independent of sort order.
    key: fqdn || ip || String(value.publicKey || ""),
    publicKey: String(value.publicKey || ""),
    relayAddress: String(value.relayAddress || ""),
    lastHandshake: isZeroTime(value.lastWireguardHandshake) ? "" : String(value.lastWireguardHandshake),
    lastStatusUpdate: isZeroTime(value.lastStatusUpdate) ? "" : String(value.lastStatusUpdate),
    iceLocal: String(ice.local || ""),
    iceRemote: String(ice.remote || ""),
    endpointLocal: String(endpoint.local || ""),
    endpointRemote: String(endpoint.remote || ""),
    status: String(value.status || "Disconnected"),
    connected: state === "connected",
    connecting: state === "connecting",
    idle: state === "idle",
    state: state,
    connectionType: String(value.connectionType || ""),
    latencyMs: latencyNs > 0 ? latencyNs / 1000000 : -1,
    received: Number(value.transferReceived || 0),
    sent: Number(value.transferSent || 0),
    networks: Array.isArray(value.networks) ? value.networks : [],
    quantumResistance: value.quantumResistance === true
  }
}

// The daemon reports far more than up/down: `Idle`, `Connecting`, `Connected`,
// `NeedsLogin`, `LoginFailed` and `SessionExpired` all mean different things
// and need different fixes, so they are kept distinct all the way to the UI.
// "daemonDown" and "missing" are added by the service for conditions the
// daemon cannot report because it is not answering at all.
function daemonState(raw) {
  switch (String(raw || "").toLowerCase()) {
    case "connected": return "connected"
    case "connecting": return "connecting"
    case "idle": return "idle"
    case "needslogin": return "needsLogin"
    case "loginfailed": return "loginFailed"
    case "sessionexpired": return "sessionExpired"
    case "": return "unknown"
    default: return "unknown"
  }
}

function stateLabel(state) {
  switch (state) {
    case "connected": return "Connected"
    case "connecting": return "Connecting…"
    case "idle": return "Disconnected"
    case "needsLogin": return "Login required"
    case "loginFailed": return "Login failed"
    case "sessionExpired": return "Session expired"
    case "daemonDown": return "Daemon not running"
    case "missing": return "Not installed"
    default: return "Unknown"
  }
}

// The one sentence that tells the user what to do about the state they are in.
function stateHint(state) {
  switch (state) {
    case "needsLogin": return "This device is not authenticated with NetBird yet."
    case "sessionExpired": return "The NetBird session expired and needs a new login."
    case "loginFailed": return "The last login attempt failed."
    case "daemonDown": return "The NetBird daemon is not answering. Start the service, then retry."
    case "missing": return "NetBird CLI is not installed or not on PATH."
    default: return ""
  }
}

function needsLoginState(state) {
  return state === "needsLogin" || state === "sessionExpired" || state === "loginFailed"
}

// `netbird status` cannot report that the daemon is unreachable: the CLI just
// retries the socket forever. Detect it from the exit code (124 = our own
// `timeout` fired) or from the gRPC dial error it prints while spinning.
function daemonUnreachable(exitCode, output) {
  if (exitCode === 124 || exitCode === 137) return true
  var text = String(output || "").toLowerCase()
  if (text === "") return false
  return text.indexOf("failed to connect to daemon") !== -1
    || text.indexOf("connection error") !== -1
    || text.indexOf("no such file or directory") !== -1
    || text.indexOf("connection refused") !== -1
}

// `netbird up` prints the SSO verification URL, and a separate code when the
// URL does not already embed it:
//
//   If your browser didn't open automatically, use this URL to log in:
//   https://example.eu.auth0.com/activate?user_code=ABCD-EFGH and enter the
//   code ABCD-EFGH to authenticate.
function parseLoginPrompt(text) {
  var value = String(text || "")
  var url = ""
  var code = ""
  var urlMatch = /https?:\/\/\S+/.exec(value)
  if (urlMatch) url = urlMatch[0].replace(/[.,)]+$/, "")
  var codeMatch = /enter the code\s+(\S+?)\s+to authenticate/i.exec(value)
  if (codeMatch) code = codeMatch[1]
  return { url: url, code: code }
}

// A CLI newer or older than the daemon is a real source of "it behaves
// strangely" reports, and both versions are already in the status payload.
function versionMismatch(cliVersion, daemonVersion) {
  var cli = String(cliVersion || "").trim()
  var daemon = String(daemonVersion || "").trim()
  if (cli === "" || daemon === "") return false
  return cli !== daemon
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: false, message: "Disconnected" }

  try {
    var data = JSON.parse(text)
    var details = data.peers && Array.isArray(data.peers.details) ? data.peers.details : []
    var peers = []
    for (var i = 0; i < details.length; i++) peers.push(normalizePeer(details[i]))
    peers.sort(function(a, b) {
      var rankA = stateRank(a.state)
      var rankB = stateRank(b.state)
      if (rankA !== rankB) return rankA - rankB
      return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
    })

    var connecting = 0
    for (var c = 0; c < peers.length; c++) if (peers[c].connecting) connecting++

    var relays = normalizeRelays(data.relays)

    var managementConnected = !!(data.management && data.management.connected)
    var signalConnected = !!(data.signal && data.signal.connected)
    var state = daemonState(data.daemonStatus)
    // Daemons too old to report `daemonStatus` still tell us whether they
    // reached management, which is the next best signal.
    if (state === "unknown") state = managementConnected ? "connected" : "idle"
    var running = state === "connected"
    var cliVersion = String(data.cliVersion || "")
    var daemonVersion = String(data.daemonVersion || "")

    return {
      ok: true,
      running: running,
      state: state,
      connecting: state === "connecting",
      needsLogin: needsLoginState(state),
      statusText: stateLabel(state),
      hint: stateHint(state),
      cliVersion: cliVersion,
      daemonVersion: daemonVersion,
      versionMismatch: versionMismatch(cliVersion, daemonVersion),
      managementConnected: managementConnected,
      signalConnected: signalConnected,
      ip: stripCidr(data.netbirdIp),
      fqdn: String(data.fqdn || ""),
      profileName: String(data.profileName || "default"),
      peers: peers,
      peerTotal: data.peers && Number.isFinite(Number(data.peers.total)) ? Number(data.peers.total) : peers.length,
      peerConnected: data.peers && Number.isFinite(Number(data.peers.connected))
        ? Number(data.peers.connected)
        : peers.filter(function(peer) { return peer.connected }).length,
      peerConnecting: connecting,
      relays: relays.details,
      relayTotal: relays.total,
      relayAvailable: relays.available
    }
  } catch (error) {
    return { ok: false, message: "Status error", error: String(error) }
  }
}

function formatLatency(ms) {
  var value = Number(ms)
  if (!isFinite(value) || value < 0) return ""
  if (value < 10) return value.toFixed(1) + " ms"
  return Math.round(value) + " ms"
}

// "stun:stun.netbird.io:443" → "stun.netbird.io", so a relay list stays
// readable in a 390px panel. Falls back to the raw URI when it does not
// look like scheme://host:port.
function relayName(uri) {
  var text = String(uri || "")
  // Strip the scheme exactly once: "rels://host:443" and "stun:host:443" are
  // both valid here, and running both patterns would eat the host as well.
  var withoutScheme = /:\/\//.test(text)
    ? text.replace(/^[a-z0-9+.-]+:\/\//i, "")
    : text.replace(/^(stun|stuns|turn|turns):/i, "")
  var host = withoutScheme.split("?")[0].split("/")[0]
  if (host.charAt(0) === "[") {
    var end = host.indexOf("]")
    if (end !== -1) return host.substring(1, end)
  }
  var parts = host.split(":")
  return parts[0] || text
}

function relayScheme(uri) {
  var match = /^([a-z0-9+.-]+):/i.exec(String(uri || ""))
  return match ? match[1].toLowerCase() : ""
}

function normalizeRelay(relay) {
  var value = relay || {}
  var uri = String(value.uri || "")
  return {
    uri: uri,
    name: relayName(uri),
    scheme: relayScheme(uri),
    available: value.available === true,
    error: String(value.error || ""),
    transport: String(value.transport || "")
  }
}

function normalizeRelays(relays) {
  var value = relays || {}
  var details = Array.isArray(value.details) ? value.details : []
  var list = []
  for (var i = 0; i < details.length; i++) list.push(normalizeRelay(details[i]))
  list.sort(function(a, b) {
    if (a.available !== b.available) return a.available ? 1 : -1
    return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
  })
  var available = 0
  for (var j = 0; j < list.length; j++) if (list[j].available) available++
  return {
    details: list,
    total: Number.isFinite(Number(value.total)) ? Number(value.total) : list.length,
    available: Number.isFinite(Number(value.available)) ? Number(value.available) : available
  }
}

function stateRank(state) {
  if (state === "connected") return 0
  if (state === "connecting") return 1
  if (state === "idle") return 2
  return 3
}

// `netbird networks list` has no --json, so parse its printed form:
//
//   Available Networks:
//
//     - ID: Proxy
//       Network: 10.0.0.172/32
//       Status: Selected
//
// Domain-based resources print `Domains:` plus a `Resolved IPs:` block of
// `      [domain]: ip, ip` lines instead of `Network:`.
function parseNetworks(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: true, networks: [] }
  if (text.indexOf("No networks available.") !== -1) return { ok: true, networks: [] }
  if (text.indexOf("Available Networks:") === -1)
    return { ok: false, networks: [], message: text.split("\n")[0] }

  var lines = text.split("\n")
  var networks = []
  var current = null

  function flush() {
    if (current) networks.push(current)
    current = null
  }

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var trimmed = line.trim()
    if (trimmed === "" || trimmed === "Available Networks:") continue

    var idMatch = /^-\s*ID:\s*(.*)$/.exec(trimmed)
    if (idMatch) {
      flush()
      current = {
        id: idMatch[1].trim(),
        range: "",
        domains: [],
        resolvedIps: [],
        selected: false,
        status: ""
      }
      continue
    }
    if (!current) continue

    var resolved = /^\[(.+?)\]:\s*(.*)$/.exec(trimmed)
    if (resolved) {
      current.resolvedIps.push({ domain: resolved[1].trim(), ips: splitList(resolved[2]) })
      continue
    }

    var field = /^([A-Za-z ]+):\s*(.*)$/.exec(trimmed)
    if (!field) continue
    var key = field[1].trim().toLowerCase()
    var value = field[2].trim()

    if (key === "network") current.range = value
    else if (key === "domains") current.domains = splitList(value)
    else if (key === "status") {
      current.status = value
      current.selected = value.toLowerCase() === "selected"
    }
  }
  flush()

  return { ok: true, networks: networks }
}

function splitList(value) {
  var text = String(value || "").trim()
  if (text === "" || text === "-") return []
  var parts = text.split(",")
  var result = []
  for (var i = 0; i < parts.length; i++) {
    var part = parts[i].trim()
    if (part !== "") result.push(part)
  }
  return result
}

// One-line summary for a network row: the CIDR for route resources, the
// domain list for domain resources.
function networkSubtitle(network) {
  if (!network) return ""
  if (network.range) return network.range
  if (network.domains && network.domains.length > 0) return network.domains.join(", ")
  return ""
}

function selectedNetworkCount(networks) {
  var list = Array.isArray(networks) ? networks : []
  var count = 0
  for (var i = 0; i < list.length; i++) if (list[i].selected) count++
  return count
}

function formatBytes(value) {
  var bytes = Number(value || 0)
  if (!isFinite(bytes) || bytes <= 0) return "0 B"
  var units = ["B", "KB", "MB", "GB", "TB"]
  var index = 0
  while (bytes >= 1024 && index < units.length - 1) {
    bytes /= 1024
    index++
  }
  var digits = index === 0 || bytes >= 100 ? 0 : 1
  return bytes.toFixed(digits) + " " + units[index]
}

// "12 seconds ago" beats an ISO timestamp nobody can read at a glance.
// `nowMs` is injectable so this stays testable.
function formatRelativeTime(value, nowMs) {
  var text = String(value || "")
  if (text === "") return "never"
  var then = Date.parse(text)
  if (!isFinite(then)) return ""
  var now = isFinite(Number(nowMs)) ? Number(nowMs) : Date.now()
  var seconds = Math.round((now - then) / 1000)
  if (seconds < 0) seconds = 0
  if (seconds < 10) return "just now"
  if (seconds < 60) return seconds + " seconds ago"
  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + (minutes === 1 ? " minute ago" : " minutes ago")
  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + (hours === 1 ? " hour ago" : " hours ago")
  var days = Math.floor(hours / 24)
  return days + (days === 1 ? " day ago" : " days ago")
}

// ICE candidate types explain *why* a connection looks the way it does.
function candidateLabel(type) {
  switch (String(type || "").toLowerCase()) {
    case "host": return "local network"
    case "srflx": return "STUN reflexive"
    case "prflx": return "peer reflexive"
    case "relay": return "TURN relay"
    case "": return ""
    default: return String(type)
  }
}

function candidatePair(peer) {
  if (!peer) return ""
  var local = candidateLabel(peer.iceLocal)
  var remote = candidateLabel(peer.iceRemote)
  if (local === "" && remote === "") return ""
  if (local === remote) return local
  return (local || "unknown") + " → " + (remote || "unknown")
}

// The answer to "why is this peer relayed?", in one sentence.
function connectionSummary(peer) {
  if (!peer) return ""
  if (peer.connecting) return "Negotiating a connection…"
  if (!peer.connected) return "Not connected"
  var type = String(peer.connectionType || "").toLowerCase()
  var pair = candidatePair(peer)
  if (type === "relayed") {
    var via = peer.relayAddress ? " via " + relayName(peer.relayAddress) : ""
    return "Relayed" + via + (pair ? " (" + pair + ")" : "")
  }
  if (type === "p2p") return "Direct peer-to-peer" + (pair ? " over " + pair : "")
  return pair || String(peer.connectionType || "")
}

// Free-text peer filter: name, FQDN, IP, connection type and routed networks
// are all things people actually search for.
function matchesPeerQuery(peer, query) {
  var text = String(query || "").trim().toLowerCase()
  if (text === "") return true
  if (!peer) return false
  var haystack = [
    peer.name,
    peer.fqdn,
    peer.ip,
    peer.connectionType,
    peer.status,
    Array.isArray(peer.networks) ? peer.networks.join(" ") : ""
  ].join(" ").toLowerCase()
  var terms = text.split(/\s+/)
  for (var i = 0; i < terms.length; i++)
    if (terms[i] !== "" && haystack.indexOf(terms[i]) === -1) return false
  return true
}

function filterPeers(peers, query, includeDisconnected) {
  var list = Array.isArray(peers) ? peers : []
  var result = []
  for (var i = 0; i < list.length; i++) {
    var peer = list[i]
    // "Connecting" is an active transition, not an offline peer. Hiding
    // disconnected peers should still leave an in-progress handshake visible.
    if (includeDisconnected === false && !peer.connected && !peer.connecting) continue
    if (matchesPeerQuery(peer, query)) result.push(peer)
  }
  return result
}

if (typeof module !== "undefined") {
  module.exports = {
    stripCidr: stripCidr,
    hostname: hostname,
    connectedStatus: connectedStatus,
    daemonState: daemonState,
    stateLabel: stateLabel,
    stateHint: stateHint,
    needsLoginState: needsLoginState,
    daemonUnreachable: daemonUnreachable,
    parseLoginPrompt: parseLoginPrompt,
    versionMismatch: versionMismatch,
    peerState: peerState,
    normalizePeer: normalizePeer,
    parseStatus: parseStatus,
    formatLatency: formatLatency,
    formatBytes: formatBytes,
    formatRelativeTime: formatRelativeTime,
    candidateLabel: candidateLabel,
    candidatePair: candidatePair,
    connectionSummary: connectionSummary,
    matchesPeerQuery: matchesPeerQuery,
    filterPeers: filterPeers,
    relayName: relayName,
    normalizeRelays: normalizeRelays,
    parseNetworks: parseNetworks,
    networkSubtitle: networkSubtitle,
    selectedNetworkCount: selectedNetworkCount
  }
}
