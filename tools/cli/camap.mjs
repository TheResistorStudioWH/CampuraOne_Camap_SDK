#!/usr/bin/env node
import {readFile,writeFile} from 'node:fs/promises';
import {decodeCamap,encodeCamap} from '../../typescript/dist/index.js';
const [action,path,out]=process.argv.slice(2);
if(!path||!['inspect','validate','to-json','from-json'].includes(action)){console.error('Usage: node tools/cli/camap.mjs inspect|validate|to-json|from-json INPUT [OUTPUT]');process.exitCode=1;}
else try {
 const bytes=await readFile(path),doc=action==='from-json'?JSON.parse(bytes.toString()):await decodeCamap(bytes);
 if(action==='from-json'){if(!out)throw Error('OUTPUT required');await writeFile(out,await encodeCamap(doc));}
 else if(action==='to-json'){if(!out)throw Error('OUTPUT required');await writeFile(out,JSON.stringify(doc,null,2)+'\n');}
 else console.log(JSON.stringify({valid:true,title:doc.title,formatVersion:doc.formatVersion,frames:doc.frames.length,features:doc.features.length,nodes:doc.nodes.length,edges:doc.edges.length,baseRevision:doc.baseRevision},null,2));
}catch(e){console.error(e.message);process.exitCode=1;}
