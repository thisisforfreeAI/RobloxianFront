// Small scalar/vector expression evaluator for local shader reference tests. Not a GLSL runtime.
// Only straight-line float/vec declarations, assignments and returns are accepted; unsupported syntax fails.
function zip(a,b,op){
 if(Array.isArray(a)||Array.isArray(b)){const n=Array.isArray(a)?a.length:b.length;return Array.from({length:n},(_,i)=>op(Array.isArray(a)?a[i]:a,Array.isArray(b)?b[i]:b));}
 return op(a,b);
}
function evaluator(source,uniforms){
 const builtins={
  fract:v=>Array.isArray(v)?v.map(x=>x-Math.floor(x)):v-Math.floor(v),
  floor:v=>Array.isArray(v)?v.map(Math.floor):Math.floor(v),
  dot:(a,b)=>a.reduce((sum,x,i)=>sum+x*b[i],0),
  mix:(a,b,t)=>zip(a,b,(x,y)=>x+(y-x)*t),step:(a,b)=>zip(a,b,(x,y)=>y<x?0:1),
 };
 for(const n of [2,3,4])builtins['vec'+n]=(...values)=>{const flat=values.flat();if(flat.length===1)return Array(n).fill(flat[0]);if(flat.length!==n)throw Error('vector size mismatch');return flat;};
 const functions={};
 const clean=source.replace(/\/\*[\s\S]*?\*\//g,'').replace(/\/\/[^\n]*/g,'');
 const pattern=/\b(float|vec[234])\s+(\w+)\(([^)]*)\)\s*\{([^{}]*)\}/g;
 for(const m of clean.matchAll(pattern))functions[m[2]]={args:m[3].split(',').filter(x=>x.trim()).map(x=>x.trim().split(/\s+/).at(-1)),statements:m[4].split(';').map(x=>x.trim()).filter(Boolean)};
 function expression(input,env){
  const tokens=input.match(/(?:\d+(?:\.\d*)?|\.\d+)(?:e[-+]?\d+)?|[A-Za-z_]\w*|[()+\-*/,\.]/gi)||[];
  if(tokens.join('')!==input.replace(/\s/g,''))throw Error('unsupported expression: '+input);
  let at=0;
  function atom(){
   let value,t=tokens[at++];
   if(t==='-')value=zip(0,atom(),(a,b)=>a-b);
   else if(t==='('){value=sum();if(tokens[at++]!==')')throw Error('expected close parenthesis');}
   else if(/^\d|^\./.test(t))value=Number(t);
   else if(tokens[at]==='('){
    at++;const args=[];if(tokens[at]!==')')do{args.push(sum());if(tokens[at]!==',')break;at++;}while(true);
    if(tokens[at++]!==')')throw Error('expected function close');value=call(t,args);
   }else{if(!(t in env))throw Error('unknown shader symbol: '+t);value=env[t];}
   while(tokens[at]==='.'){
    at++;const swizzle=tokens[at++],indices=[...swizzle].map(ch=>'xyzw'.indexOf(ch));
    if(!Array.isArray(value)||indices.some(i=>i<0||i>=value.length))throw Error('invalid swizzle');
    value=indices.length===1?value[indices[0]]:indices.map(i=>value[i]);
   }
   return value;
  }
  function product(){let value=atom();while(tokens[at]==='*'||tokens[at]==='/'){const op=tokens[at++],rhs=atom();value=zip(value,rhs,op==='*'?(a,b)=>a*b:(a,b)=>a/b);}return value;}
  function sum(){let value=product();while(tokens[at]==='+'||tokens[at]==='-'){const op=tokens[at++],rhs=product();value=zip(value,rhs,op==='+'?(a,b)=>a+b:(a,b)=>a-b);}return value;}
  const value=sum();if(at!==tokens.length)throw Error('unused shader tokens');return value;
 }
 function call(name,args){
  if(builtins[name])return builtins[name](...args);
  const fn=functions[name];if(!fn)throw Error('unknown shader function: '+name);
  const env={...uniforms};fn.args.forEach((name,i)=>{env[name]=args[i];});
  for(const statement of fn.statements){
   if(statement.startsWith('return '))return expression(statement.slice(7),env);
   const m=/^(?:(?:float|vec[234])\s+)?(\w+)\s*(\+=|=)\s*(.+)$/.exec(statement);
   if(!m)throw Error('unsupported shader statement: '+statement);
   const value=expression(m[3],env);env[m[1]]=m[2]==='='?value:zip(env[m[1]],value,(a,b)=>a+b);
  }
  throw Error('shader function has no return: '+name);
 }
 return {call};
}
module.exports={evaluator};
