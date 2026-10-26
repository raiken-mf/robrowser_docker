// Run inside the wsProxy container: node - [url] [timeoutMs] < this-file
const WebSocket = require('/opt/wsproxy/node_modules/ws');

const url = process.argv[2] || 'ws://127.0.0.1:5999/ragnarok-login:6900';
const timeoutMs = Number(process.argv[3] || 30000);
if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) {
  throw new Error('timeoutMs must be a positive number');
}

let socket;
let retry;
let attempts = 0;
let lastError = 'No connection established';
const deadline = setTimeout(() => {
  clearTimeout(retry);
  console.error(`WebSocket handshake timed out after ${timeoutMs}ms (${attempts} attempts): ${lastError}`);
  process.exit(1);
}, timeoutMs);

function connect() {
  attempts += 1;
  socket = new WebSocket(url, { handshakeTimeout: 1000 });
  socket.once('open', () => {
    clearTimeout(deadline);
    console.log(`WebSocket handshake succeeded after ${attempts} attempt(s)`);
    socket.terminate();
    process.exit(0);
  });
  socket.once('error', (error) => {
    lastError = error.message;
    socket.terminate();
    retry = setTimeout(connect, 250);
  });
}

connect();
