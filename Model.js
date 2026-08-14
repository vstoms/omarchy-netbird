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

function normalizePeer(peer) {
  var value = peer || {}
  var latencyNs = Number(value.latency || 0)
  return {
    fqdn: String(value.fqdn || ""),
    name: hostname(value.fqdn, value.netbirdIp),
    ip: stripCidr(value.netbirdIp),
    status: String(value.status || "Disconnected"),
    connected: connectedStatus(value.status),
    connectionType: String(value.connectionType || ""),
    latencyMs: latencyNs > 0 ? latencyNs / 1000000 : -1,
    received: Number(value.transferReceived || 0),
    sent: Number(value.transferSent || 0),
    networks: Array.isArray(value.networks) ? value.networks : [],
    quantumResistance: value.quantumResistance === true
  }
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
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
    })

    var managementConnected = !!(data.management && data.management.connected)
    var signalConnected = !!(data.signal && data.signal.connected)
    var daemonConnected = connectedStatus(data.daemonStatus)
    var running = managementConnected || daemonConnected

    return {
      ok: true,
      running: running,
      statusText: running ? "Connected" : String(data.daemonStatus || "Disconnected"),
      managementConnected: managementConnected,
      signalConnected: signalConnected,
      ip: stripCidr(data.netbirdIp),
      fqdn: String(data.fqdn || ""),
      profileName: String(data.profileName || "default"),
      peers: peers,
      peerTotal: data.peers && Number.isFinite(Number(data.peers.total)) ? Number(data.peers.total) : peers.length,
      peerConnected: data.peers && Number.isFinite(Number(data.peers.connected))
        ? Number(data.peers.connected)
        : peers.filter(function(peer) { return peer.connected }).length
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

if (typeof module !== "undefined") {
  module.exports = {
    stripCidr: stripCidr,
    hostname: hostname,
    connectedStatus: connectedStatus,
    normalizePeer: normalizePeer,
    parseStatus: parseStatus,
    formatLatency: formatLatency
  }
}
