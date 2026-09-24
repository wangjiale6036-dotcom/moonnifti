// Reproducible estimates, NOT an organizer-certified "effective line" formula.
import fs from 'node:fs';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const argv = process.argv.slice(2);
const refAt = argv.indexOf('--ref');
const ref = refAt < 0 ? null : argv[refAt + 1];
const git = (...args) => execFileSync('git', args, {cwd:root, encoding:'utf8'}).trim();
const names = [...new Set((ref ? git('ls-tree','-r','--name-only',ref) : git('ls-files','--cached','--others','--exclude-standard')).split(/\r?\n/))]
  .filter(name => name.endsWith('.mbt') && !/_(?:wb)?test\.mbt$/.test(name) && !name.endsWith('.generated.mbt'));
function stripComment(line) {
  let quote = false, escaped = false;
  for (let i = 0; i < line.length; i++) {
    if (escaped) {escaped=false; continue;}
    if (quote && line[i] === '\\') {escaped=true; continue;}
    if (line[i] === '"') {quote=!quote; continue;}
    if (!quote && line.slice(i,i+2)==='//') return line.slice(0,i);
  }
  return line;
}
const rows = names.map(file => {
  const data = ref ? execFileSync('git',['show',`${ref}:${file}`],{cwd:root,encoding:'utf8'}) : fs.readFileSync(path.join(root,file),'utf8');
  const lines = data.replace(/\r\n/g,'\n').replace(/\n$/,'').split('\n');
  const code = lines.filter(line => !/^\s*(?:#\||extern "js")/.test(line)).map(stripComment).filter(line => line.trim());
  return {file,core:!file.includes('/'),physical:lines.length,nonblank_noncomment_moonbit:code.length,
    without_delimiter_only_lines:code.filter(line => /[\p{L}\p{N}_]/u.test(line)).length};
});
const sum = list => Object.fromEntries(['physical','nonblank_noncomment_moonbit','without_delimiter_only_lines'].map(key => [key,list.reduce((n,row) => n+row[key],0)]));
const report = {basis:ref ?? 'working-tree',method:'Exclude tests, generated files, blank/comment-only lines, JS FFI bodies/declarations; additionally show a conservative delimiter-only exclusion. No claim of official effective LOC.',core:sum(rows.filter(r=>r.core)),all_production:sum(rows),files:rows};
const outAt=argv.indexOf('--report');
if(outAt>=0){const target=path.resolve(root,argv[outAt+1]);fs.mkdirSync(path.dirname(target),{recursive:true});fs.writeFileSync(target,JSON.stringify(report,null,2)+'\n');}
console.log(JSON.stringify(report,null,2));
if(argv.includes('--check') && report.core.without_delimiter_only_lines<1000) process.exitCode=1;
