import { createServer } from "node:http";
import { randomBytes } from "node:crypto";
import { WebSocketServer, WebSocket } from "ws";

const PORT = Number.parseInt(process.env.PORT ?? "8080", 10);
const MAX_PLAYERS = Math.min(Math.max(Number.parseInt(process.env.MAX_PLAYERS ?? "4", 10), 2), 8);
const PROTOCOL_VERSION = 1;
const ALLOWED_ORIGINS = new Set(
  (process.env.ALLOWED_ORIGINS ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean),
);

if (ALLOWED_ORIGINS.size === 0) {
  throw new Error("ALLOWED_ORIGINS must list the HTTPS game origin(s), comma-separated.");
}

/** @type {Map<string, Lobby>} */
const lobbies = new Map();

/** @typedef {{ id: number, name: string, ready: boolean, socket: import('ws').WebSocket, lobby: Lobby | null }} Client */
/** @typedef {{ code: string, hostId: number, started: boolean, nextPeerId: number, clients: Map<number, Client> }} Lobby */

const http = createServer((request, response) => {
  if (request.url === "/healthz") {
    response.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
    response.end(JSON.stringify({ ok: true, lobbies: lobbies.size }));
    return;
  }
  response.writeHead(404, { "content-type": "application/json" });
  response.end(JSON.stringify({ error: "not found" }));
});

const wss = new WebSocketServer({
  server: http,
  maxPayload: 16 * 1024,
  perMessageDeflate: false,
  verifyClient: ({ origin }, done) => done(ALLOWED_ORIGINS.has(origin), 403, "Origin is not allowed"),
});

wss.on("connection", (socket) => {
  /** @type {Client} */
  const client = { id: 0, name: "", ready: false, socket, lobby: null };
  socket.on("message", (raw, isBinary) => {
    if (isBinary) {
      reject(client, "Binary signaling messages are not supported.");
      return;
    }
    let message;
    try {
      message = JSON.parse(raw.toString());
    } catch {
      reject(client, "Malformed JSON.");
      return;
    }
    if (!message || typeof message !== "object" || Array.isArray(message)) {
      reject(client, "Message must be an object.");
      return;
    }
    handle(client, message);
  });
  socket.on("close", () => leave(client));
  socket.on("error", () => leave(client));
});

function handle(client, message) {
  switch (message.type) {
    case "create":
      if (message.protocol !== PROTOCOL_VERSION) return reject(client, "Unsupported lobby protocol.");
      if (client.lobby) return reject(client, "Leave the current lobby first.");
      createLobby(client, cleanName(message.name));
      return;
    case "join":
      if (message.protocol !== PROTOCOL_VERSION) return reject(client, "Unsupported lobby protocol.");
      if (client.lobby) return reject(client, "Leave the current lobby first.");
      joinLobby(client, String(message.lobby ?? "").toUpperCase(), cleanName(message.name));
      return;
    case "ready":
      if (!client.lobby || client.lobby.started) return reject(client, "Lobby is unavailable.");
      client.ready = message.ready === true;
      broadcastLobbyState(client.lobby);
      return;
    case "start":
      startLobby(client);
      return;
    case "signal":
      relaySignal(client, message);
      return;
    case "leave":
      leave(client);
      return;
    default:
      reject(client, "Unknown lobby message.");
  }
}

function createLobby(client, name) {
  const code = uniqueLobbyCode();
  /** @type {Lobby} */
  const lobby = { code, hostId: 1, started: false, nextPeerId: 2, clients: new Map() };
  client.id = 1;
  client.name = name;
  client.ready = true;
  client.lobby = lobby;
  lobby.clients.set(client.id, client);
  lobbies.set(code, lobby);
  broadcastLobbyState(lobby);
}

function joinLobby(client, code, name) {
  const lobby = lobbies.get(code);
  if (!lobby) return reject(client, "Lobby not found.");
  if (lobby.started) return reject(client, "That shift has already started.");
  if (lobby.clients.size >= MAX_PLAYERS) return reject(client, "That lobby is full.");
  client.id = lobby.nextPeerId++;
  client.name = name;
  client.ready = false;
  client.lobby = lobby;
  lobby.clients.set(client.id, client);
  broadcastLobbyState(lobby);
}

function startLobby(client) {
  const lobby = client.lobby;
  if (!lobby || client.id !== lobby.hostId) return reject(client, "Only the host can start the shift.");
  if (lobby.clients.size < 2) return reject(client, "A lobby needs at least two players.");
  if ([...lobby.clients.values()].some((member) => !member.ready)) {
    return reject(client, "Every crew member must be ready.");
  }
  lobby.started = true;
  broadcast(lobby, { type: "match_started" });
}

function relaySignal(client, message) {
  const lobby = client.lobby;
  const to = Number(message.to);
  const data = message.data;
  if (!lobby || !Number.isSafeInteger(to) || to <= 0 || !data || typeof data !== "object" || Array.isArray(data)) {
    return reject(client, "Invalid signaling relay.");
  }
  const recipient = lobby.clients.get(to);
  if (!recipient) return reject(client, "Requested peer is not in this lobby.");
  send(recipient, { type: "signal", from: client.id, data });
}

function leave(client) {
  const lobby = client.lobby;
  if (!lobby) return;
  client.lobby = null;
  lobby.clients.delete(client.id);
  if (client.id === lobby.hostId) {
    broadcast(lobby, { type: "lobby_closed" });
    for (const member of lobby.clients.values()) member.lobby = null;
    lobbies.delete(lobby.code);
    return;
  }
  if (lobby.clients.size === 0) {
    lobbies.delete(lobby.code);
    return;
  }
  broadcastLobbyState(lobby);
}

function broadcastLobbyState(lobby) {
  const members = [...lobby.clients.values()].map(({ id, name, ready }) => ({ id, name, ready }));
  for (const member of lobby.clients.values()) {
    send(member, { type: "lobby_state", lobby: lobby.code, self: member.id, host: lobby.hostId, members });
  }
}

function broadcast(lobby, message) {
  for (const member of lobby.clients.values()) send(member, message);
}

function send(client, message) {
  if (client.socket.readyState === WebSocket.OPEN) client.socket.send(JSON.stringify(message));
}

function reject(client, message) {
  send(client, { type: "error", message });
}

function cleanName(value) {
  return String(value ?? "Night Crew").trim().slice(0, 20) || "Night Crew";
}

function uniqueLobbyCode() {
  let code;
  do {
    code = randomBytes(4).toString("base64url").slice(0, 6).toUpperCase();
  } while (lobbies.has(code));
  return code;
}

http.listen(PORT, "0.0.0.0", () => {
  console.log(`Signaling service listening on :${PORT}; max players: ${MAX_PLAYERS}`);
});
