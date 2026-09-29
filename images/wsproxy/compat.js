const fs = require('node:fs');
const path = require('node:path');

const serverPath = path.join(__dirname, 'node_modules/wsproxy/src/server.js');
const source = fs.readFileSync(serverPath, 'utf8');
const legacyHandler = 'function onConnection(ws) {';
const compatibleHandler = 'function onConnection(ws, request) {\n\tws.upgradeReq = request;';

if (source.includes(compatibleHandler)) {
  process.exit(0);
}

if (!source.includes(legacyHandler)) {
  throw new Error(`Unsupported wsproxy server.js layout: ${serverPath}`);
}

fs.writeFileSync(serverPath, source.replace(legacyHandler, compatibleHandler));
