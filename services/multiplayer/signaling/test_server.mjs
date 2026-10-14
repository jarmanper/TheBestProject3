import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import test from "node:test";
import { WebSocket } from "ws";

const PORT = 18183;
const ORIGIN = "https://example.github.io";

function waitForMessage(socket, predicate, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      socket.off("message", onMessage);
      reject(new Error("Timed out waiting for signaling message."));
    }, timeoutMs);
    const onMessage = (raw) => {
      const message = JSON.parse(raw.toString());
      if (!predicate(message)) return;
      clearTimeout(timeout);
      socket.off("message", onMessage);
      resolve(message);
    };
    socket.on("message", onMessage);
  });
}

function connect() {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(`ws://127.0.0.1:${PORT}`, { headers: { origin: ORIGIN } });
    socket.once("open", () => resolve(socket));
    socket.once("error", reject);
  });
}

test("creates, joins, readies, and starts a lobby", async () => {
  const service = spawn(process.execPath, ["server.js"], {
    cwd: import.meta.dirname,
    env: { ...process.env, PORT: String(PORT), ALLOWED_ORIGINS: ORIGIN },
    stdio: ["ignore", "pipe", "pipe"],
  });
	await new Promise((resolve, reject) => {
		const timeout = setTimeout(() => reject(new Error("Signaling service did not start.")), 3000);
		service.stdout.on("data", (data) => {
			if (!data.toString().includes("Signaling service listening")) return;
			clearTimeout(timeout);
			resolve();
		});
		service.once("error", reject);
	});
  const host = await connect();
  const guest = await connect();
  try {
    const hostState = waitForMessage(host, (message) => message.type === "lobby_state" && message.self === 1);
    host.send(JSON.stringify({ type: "create", protocol: 1, name: "Host" }));
    const created = await hostState;
    assert.equal(created.host, 1);
    assert.equal(created.members.length, 1);

    const hostUpdated = waitForMessage(host, (message) => message.type === "lobby_state" && message.members.length === 2);
    const guestJoined = waitForMessage(guest, (message) => message.type === "lobby_state" && message.self === 2);
    guest.send(JSON.stringify({ type: "join", protocol: 1, lobby: created.lobby, name: "Guest" }));
    assert.equal((await hostUpdated).members[1].name, "Guest");
    assert.equal((await guestJoined).members.length, 2);

    const hostReady = waitForMessage(host, (message) => message.type === "lobby_state" && message.members.every((member) => member.ready));
    guest.send(JSON.stringify({ type: "ready", ready: true }));
    await hostReady;

    const hostStarted = waitForMessage(host, (message) => message.type === "match_started");
    const guestStarted = waitForMessage(guest, (message) => message.type === "match_started");
    host.send(JSON.stringify({ type: "start" }));
    await Promise.all([hostStarted, guestStarted]);
  } finally {
    host.close();
    guest.close();
    service.kill();
  }
});
