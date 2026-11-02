import fs from 'fs';
import path from 'path';
import { it, expect } from 'vitest';
import CLua from 'Vendors/wasmoon-lua5.1.js';
import LuaModuleLoader from 'Core/LuaModuleLoader.js';

it('loads nested SystemEN require and dofile through the actual VFS loader and HTTP', async () => {
  const wasm = fs.readFileSync(path.resolve('src/Vendors/liblua5.1.wasm'));
  const lua = await CLua.Lua.create({ customWasmUri: `data:application/octet-stream;base64,${wasm.toString('base64')}` });
  const seen = [];
  const vfsLoader = async candidate => {
    seen.push(candidate);
    const response = await fetch(process.env.LUA_HTTP_BASE + candidate);
    if (!response.ok) throw new Error('not found');
    return new Uint8Array(await response.arrayBuffer());
  };
  try {
    expect(await LuaModuleLoader.doFileAsync(lua, 'SystemEN/probe-main.lua', { vfsLoader })).toBe(42);
    expect(seen).toContain('SystemEN/LuaFiles514/itemInfo_f.lua');
    expect(seen).toContain('SystemEN/LuaFiles514/probe-dofile.lua');
  } finally { lua.global.close(); }
}, 30000);
