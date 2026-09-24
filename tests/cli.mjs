import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {once} from 'node:events';
const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const cli = path.join(root, '_build/js/release/build/cmd/moonnifti/moonnifti.js');
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'moonnifti-cli-'));
let checks = 0;
function call(args, expected = 0, json = true) {
  const p = spawnSync(process.execPath, [cli, ...args.map(String)], {encoding:'utf8', timeout:30000});
  assert.equal(p.status, expected, `${args}: ${p.stderr}`);
  checks++;
  if (expected === 1) {assert.match(p.stderr, /^moonnifti:/); assert.equal(p.stdout, '');}
  return json && p.stdout ? JSON.parse(p.stdout) : p.stdout;
}
function fixture() {
  const b = Buffer.alloc(352 + 48);
  b.writeInt32LE(348, 0); b.writeInt16LE(3, 40);
  [4, 3, 2].forEach((v, i) => {b.writeInt16LE(v, 42 + 2 * i); b.writeFloatLE(1, 80 + 4 * i);});
  b.writeInt16LE(4, 70); b.writeInt16LE(16, 72); b.writeFloatLE(352, 108);
  b.writeFloatLE(1, 76); b.writeInt16LE(1, 252); b[123] = 2;
  b.write('n+1\0', 344, 'ascii');
  for (let i = 0; i < 24; i++) b.writeInt16LE(i - 12, 352 + 2 * i);
  return b;
}
try {
  assert.match(call(['--help'], 0, false), /research data/);
  assert.equal(call(['--version'], 0, false).trim(), '0.2.0');
  const input = path.join(dir, 'volume.nii'), gz = path.join(dir, 'volume.nii.gz');
  fs.writeFileSync(input, fixture()); fs.writeFileSync(gz, zlib.gzipSync(fixture()));
  assert.deepEqual(call(['dump', input]), call(['dump', gz]));
  assert.deepEqual(call(['world', input, 1, 2, 3, 'qform']).world, [1, 2, 3]);
  assert.equal(call(['grid', input, gz]).compatible, true);
  assert.deepEqual(call(['slice', input, 2, 1]).values, Array.from({length:12}, (_,i) => i));
  const out = path.join(dir, 'roi.nii.gz');
  const crop = call(['crop', input, out, 1, 1, 0, 2, 2, 2]);
  assert.deepEqual(crop.image.shape, [2,2,2]);
  assert.deepEqual(call(['dump', out]).raw, [-7,-6,-3,-2,5,6,9,10]);
  const before = fs.readFileSync(out);
  call(['crop', input, out, 0,0,0,1,1,1], 1);
  assert.deepEqual(fs.readFileSync(out), before);
  const inputBefore = fs.readFileSync(input);
  call(['crop', input, input, 0,0,0,1,1,1], 1);
  assert.deepEqual(fs.readFileSync(input), inputBefore);
  call(['crop', input, dir, 0,0,0,1,1,1], 1);
  call(['crop', input, path.join(dir,'missing','out.nii'), 0,0,0,1,1,1], 1);
  for (const args of [[], ['-1',0,0,1,1,1], [0,0,0,99999,1,1], ['01',0,0,1,1,1]])
    call(['crop', input, path.join(dir, 'invalid.nii'), ...args], 1);
  assert.equal(fs.existsSync(path.join(dir, 'invalid.nii')), false);
  const oriented = path.join(dir, 'oriented.nii');
  call(['reorient', input, oriented, 2,0,1,1,0,0]);
  assert.deepEqual(call(['inspect', oriented]).shape, [2,4,3]);
  call(['reorient', input, path.join(dir,'bad.nii'), 0,0,2,0,0,0], 1);
  call(['reorient', input, path.join(dir,'bad.nii'), 0,1,2,2,0,0], 1);
  call(['world', input, 0,0,0,'sform'], 1);
  call(['world', input, 'NaN',0,0], 1);
  call(['slice', input, 3, 0], 1);
  call(['slice', input, 0, -1], 1);
  call(['slice', input, 0, 0, 1], 1);
  call(['grid', input, input, -1], 1);
  call(['inspect', dir], 1);
  call(['inspect', path.join(dir,'absent')], 1);
  call(['unknown', input], 1);
  call(['inspect', input, 'extra'], 1);
  for (const [name, bytes] of [['empty', Buffer.alloc(0)], ['short', fixture().subarray(0,351)], ['trailing', Buffer.concat([fixture(),Buffer.alloc(1)])], ['gzip', Buffer.from([31,139,1,2,3])]]) {
    const file = path.join(dir,name); fs.writeFileSync(file,bytes); call(['inspect',file],1);
  }
  const large = path.join(dir, 'too-large.nii');
  fs.closeSync(fs.openSync(large, 'w')); fs.truncateSync(large, 268435457);
  call(['inspect', large], 1);
  // Decompressed limit tested without allocating the full fixture in this process.
  const bomb = path.join(dir, 'too-large.nii.gz');
  const compressor = zlib.createGzip(); const stream = fs.createWriteStream(bomb);
  compressor.pipe(stream); const completed = once(stream, 'finish');
  const chunk = Buffer.alloc(1048576);
  for (let i=0; i<257; i++) if (!compressor.write(chunk)) await once(compressor, 'drain');
  compressor.end(); await completed;
  call(['inspect', bomb], 1);
  assert.equal(fs.readdirSync(dir).some(x => x.startsWith('.moonnifti-')), false);
  console.log(JSON.stringify({status:'passed', cli_invocations:checks, gzip_limit_test:true}));
} finally {
  // Only this freshly-created, process-owned test directory is removed.
  fs.rmSync(dir, {recursive:true, force:true});
}
