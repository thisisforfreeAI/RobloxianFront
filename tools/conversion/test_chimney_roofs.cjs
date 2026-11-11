// Synthetic placement regressions; node --test tools/conversion/test_chimney_roofs.cjs
const {test}=require('node:test'),assert=require('node:assert/strict');
const {anchorTowns}=require('./chimney_roofs.cjs');
function scene(){
 const width=40,height=30,codes=new Uint8Array(width*height),game={w:20,h:15,urban:Array(300).fill(1),road:Array(300).fill(0)};
 const map={size:2,width,height,code(x,y){return x<0||y<0||x>=width||y>=height?0:codes[y*width+x];}};
 const roof=(x0,y0,x1,y1,code=228)=>{for(let y=y0;y<=y1;y++)for(let x=x0;x<=x1;x++)codes[y*width+x]=code;};
 const town=sites=>[{id:1,x:8,y:7,radius:8,chimneys:sites.map(([x,y],i)=>({x,y,seed:i/10}))}];
 return {map,game,roof,town};
}
test('off-roof source snaps onto a raised roof interior, preserving seed',()=>{
 const {map,game,roof,town}=scene();roof(14,10,20,17);
 const result=anchorTowns(town([[6,6]]),map,game),p=result.towns[0].chimneys[0];
 assert.ok(p);assert.equal(p.x,7.75);assert.equal(p.y,5.75);assert.equal(p.seed,0);
 assert.equal(result.audit[0].sourceOnRoof,false);
});
test('no nearby roof suppresses the emitter instead of falling back to empty ground',()=>{
 const {map,game,town}=scene();const result=anchorTowns(town([[6,6]]),map,game);
 assert.equal(result.towns[0].chimneys.length,0);assert.equal(result.audit[0].anchor,null);
});
test('low platforms, road cells and non-urban roofs are ineligible',()=>{
 const {map,game,roof,town}=scene();roof(8,8,22,22,225);
 assert.equal(anchorTowns(town([[7,7]]),map,game).towns[0].chimneys.length,0);
 roof(8,8,22,22);game.road.fill(1);
 assert.equal(anchorTowns(town([[7,7]]),map,game).towns[0].chimneys.length,0);
 game.road.fill(0);game.urban.fill(0);
 assert.equal(anchorTowns(town([[7,7]]),map,game).towns[0].chimneys.length,0);
});
test('nearby guesses do not collapse into one smoke origin and generation is deterministic',()=>{
 const {map,game,roof,town}=scene();roof(10,8,28,22);
 const input=town([[7,7],[7.01,7]]),before=JSON.stringify(input);
 const a=anchorTowns(input,map,game),b=anchorTowns(input,map,game),[p,q]=a.towns[0].chimneys;
 assert.ok(p&&q);assert.ok(Math.hypot(p.x-q.x,p.y-q.y)>=.75);
 assert.deepEqual(a,b);assert.equal(JSON.stringify(input),before);
});
test('map edges and narrow roof strips cannot yield an emitter outside a real roof interior',()=>{
 const {map,game,roof,town}=scene();roof(0,0,1,20);
 const result=anchorTowns(town([[.1,.1]]),map,game);
 assert.equal(result.towns[0].chimneys.length,0);
});
