// Exercise the real api.js and Vite-served bootstrap without starting the game.
// Only the engine execution is stubbed; its real URL is separately HTTP-checked.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const base = 'http://127.0.0.1:3000';
const tick = () => new Promise(setImmediate);
async function until(predicate) {
  for (let i=0; i<100; i++) { if (predicate()) return; await tick(); }
  assert.fail('API handshake did not settle');
}

function checkParentApi() {
  let frame, timer, messageHandler, cleared=false, ready=false;
  const sent=[];
  const target={firstChild:null, appendChild(element) { frame=element; }};
  const window={
    addEventListener(type,handler) { assert.equal(type,'message'); messageHandler=handler; },
    removeEventListener() {},
  };
  const context=vm.createContext({window, location:{hash:'#iframe-fixture'},
    document:{
      getElementsByTagName:()=>[{src:base+'/applications/api/api.js'}],
      createElement:()=>({style:{},setAttribute(){},contentWindow:{postMessage:(...args)=>sent.push(args)}}),
      getElementById:()=>null,
    },
    setInterval(callback) { timer=callback; return 42; },
    clearInterval(id) { assert.equal(id,42); cleared=true; },
  });
  vm.runInContext(fs.readFileSync('/app/applications/api/api.js','utf8'),context);
  const client=new window.ROBrowser({type:window.ROBrowser.TYPE.FRAME,target,fixture:'parent-config'});
  client.onReady=()=>{ready=true;};
  client.start();
  const url=new URL(frame.src);
  assert.equal(url.pathname,'/applications/api/api.html');
  assert.match(url.search,/^\?0\.\d+$/);
  assert.equal(url.hash,'#iframe-fixture');
  timer();
  assert.equal(sent[0][0].fixture,'parent-config');
  assert.equal(sent[0][1],'*');
  messageHandler({origin:base,source:frame.contentWindow,data:'ready'});
  assert.ok(cleared && ready,'Parent must stop polling and call onReady');
  console.log('PASS actual api.js: random query/hash, iframe config polling and ready callback');
}

async function checkBootstrap(code, sender, rejectEngine=false) {
  const listeners=new Map(), replies=[], errors=[];
  const parent={postMessage:(...args)=>replies.push(args)};
  const opener={postMessage:(...args)=>replies.push(args)};
  const window={parent,opener};
  const context=vm.createContext({window,
    addEventListener(type,handler) { assert.equal(type,'message'); listeners.set(type,handler); },
    removeEventListener(type,handler) { assert.equal(listeners.get(type),handler); listeners.delete(type); },
    console:{error:(...args)=>errors.push(args)},
  });
  let resolveEngine, imports=0;
  const gate=new Promise(resolve=>{resolveEngine=resolve;});
  const module=new vm.SourceTextModule(code,{context,identifier:base+'/applications/api/api-bootstrap.js',
    importModuleDynamically:async (specifier,ref)=>{
      imports++;
      assert.equal(new URL(specifier,ref.identifier).pathname,'/src/main.js');
      await gate;
      if (rejectEngine) throw new Error('fixture engine failure');
      const engine=new vm.SourceTextModule('globalThis.engineConfig=window.ROConfig; export const initialized=true;',{context});
      await engine.link(()=>assert.fail('Unexpected fixture import'));
      await engine.evaluate();
      return engine;
    },
  });
  await module.link(()=>assert.fail('Unexpected static bootstrap import'));
  await module.evaluate();
  listeners.get('message')({source:{},data:{fixture:'untrusted'}});
  assert.equal(window.ROConfig,undefined,'Unknown windows must not initialize the engine');
  assert.equal(imports,0);
  const config={fixture:sender};
  listeners.get('message')({source:sender==='parent'?parent:opener,data:config});
  assert.equal(listeners.size,0,'Configuration listener must be one-shot');
  assert.equal(window.ROConfig,config,'Assign configuration before importing the engine');
  await until(()=>imports===1);
  assert.equal(replies.length,0,'Do not signal ready before engine import resolves');
  resolveEngine();
  await until(()=>replies.length || errors.length);
  if (rejectEngine) {
    assert.equal(replies.length,0);
    assert.equal(errors[0][0],'Failed to load roBrowser engine:');
  } else {
    assert.equal(context.engineConfig,config);
    assert.deepEqual(replies,[['ready','*']]);
    assert.equal(errors.length,0);
  }
  assert.equal(imports,1);
  console.log(`PASS Vite bootstrap: ${sender}, source guard, one-shot config, deferred dynamic import, ${rejectEngine?'failure without ready':'ready reply'}`);
}

(async()=>{
  checkParentApi();
  const response=await fetch(base+'/applications/api/api-bootstrap.js');
  assert.equal(response.status,200);
  const code=await response.text();
  await checkBootstrap(code,'parent');
  await checkBootstrap(code,'opener');
  await checkBootstrap(code,'parent',true);
})().catch(error=>{console.error(error);process.exitCode=1;});
