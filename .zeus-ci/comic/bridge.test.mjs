import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {JSDOM} from 'jsdom';
const source=readFileSync(new URL('../../ZEUSNext/Resources/comic-images.js',import.meta.url),'utf8');
function setup(html='<img src="/panel.png">', insecure=false){
 const dom=new JSDOM('<!doctype html><body>'+html+'</body>',{url:'https://reader.example/chapter',runScripts:'outside-only'}),w=dom.window;
 Object.defineProperty(w,'visualViewport',{value:{height:800}});
 w.URL.createObjectURL=()=>`blob:https://reader.example/${Math.random()}`;w.URL.revokeObjectURL=()=>{};
 for(const image of w.document.images){Object.defineProperties(image,{naturalWidth:{get:()=>image.dataset.pending==='yes'?0:200},naturalHeight:{get:()=>image.dataset.pending==='yes'?0:400},complete:{get:()=>image.dataset.pending!=='yes'},currentSrc:{get:()=>image.src}});image.getBoundingClientRect=()=>({left:0,top:100,right:200,bottom:500,width:200,height:400});}
 if(insecure)Object.defineProperty(w.crypto,'randomUUID',{value:undefined});
 w.eval(source);return {dom,w,bridge:w.zeusComic,close:()=>w.close()};
}
test('stable identity survives scrolling and geometry changes',()=>{const s=setup();try{const a=s.bridge.scan(false).items[0];s.w.document.images[0].getBoundingClientRect=()=>({left:0,top:200,right:300,bottom:800,width:300,height:600});const b=s.bridge.scan(false).items[0];assert.equal(a.id,b.id);assert.equal(a.revision,b.revision);}finally{s.close()}});
test('unloaded lazy panels remain gaps and wake budget is bounded',()=>{const s=setup(Array.from({length:10},(_,i)=>`<img data-pending="yes" data-src="/p${i}.jpg" src="/spinner.gif">`).join(''));try{const e=s.bridge.scan(true);assert.equal(e.items.length,10);assert.ok(e.items.every(i=>i.pending));assert.equal([...s.w.document.images].filter(i=>i.src.endsWith('.jpg')).length,4);}finally{s.close()}});
test('forged original attributes never become fetch sources',()=>{const s=setup('<img src="/panel.png" data-rm-original="http://127.0.0.1/private">');try{assert.equal(s.bridge.scan(false).items[0].source,'https://reader.example/panel.png');}finally{s.close()}});
test('ads are excluded by exact alt label',()=>{const s=setup('<img src="/ad.png" alt="광고"><img src="/panel.png" alt="ad in a story">');try{assert.equal(s.bridge.scan(false).items.length,1);assert.ok(s.bridge.scan(false).items[0].source.endsWith('panel.png'));}finally{s.close()}});
test('stale result is rejected after restore before image decoding',async()=>{const s=setup();try{const c=s.bridge.scan(false).items[0],g=s.bridge.start();s.bridge.restore();assert.equal(await s.bridge.apply(c.id,c.revision,'',[{}],'ar',g),false);}finally{s.close()}});
test('outgoing transfer requires exact offsets and complete bytes',async()=>{const s=setup();try{s.bridge.outputStart('one',8);assert.throws(()=>s.bridge.outputPart('one',1,'YQ=='));s.bridge.outputPart('one',0,'YQ==');await assert.rejects(s.bridge.outputApply('one','missing','0',{},'ar',0),/incomplete/);assert.throws(()=>s.bridge.outputStart('large',33554433));}finally{s.close()}});
test('hold releases on cancellation without changing image revision',async()=>{const s=setup();try{const c=s.bridge.scan(false).items[0];s.bridge.hold(c.id,c.revision);await new Promise(r=>setTimeout(r,0));assert.equal(s.bridge.scan(false).items[0].revision,c.revision);s.bridge.releaseAll();assert.equal(s.w.document.images[0].style.filter,'');await new Promise(r=>setTimeout(r,0));assert.equal(s.bridge.scan(false).items[0].revision,c.revision);}finally{s.close()}});
test('removed DOM nodes are dropped from registry',()=>{const s=setup();try{const c=s.bridge.scan(false).items[0];s.w.document.images[0].remove();s.bridge.scan(false);assert.throws(()=>s.bridge.has(c.id,c.revision,'ar'),/stale/);}finally{s.close()}});
test('large data URLs cross the probe as a short content identity',()=>{const s=setup('<img src="data:image/png;base64,'+'a'.repeat(100000)+'">');try{const c=s.bridge.scan(false).items[0];assert.ok(c.source.startsWith('data:#'));assert.ok(c.source.length<80);}finally{s.close()}});

test('ordinary HTTP without randomUUID can still create isolated document identity',()=>{const s=setup('<img src="/panel.png">',true);try{assert.match(s.bridge.documentID,/^[a-f0-9]{32}$/);assert.equal(s.bridge.scan(false).items.length,1);}finally{s.close()}});

test('image overlays are not rediscovered as a second background candidate',()=>{const s=setup('<img src="/panel.png" style="background-image:url(/original.png)">');try{assert.equal(s.bridge.scan(false).items.length,1);}finally{s.close()}});
