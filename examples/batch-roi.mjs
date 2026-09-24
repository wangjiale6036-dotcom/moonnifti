// Downstream process integration: no imaging algorithms live in this adapter.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
function run() {
  const args = process.argv.slice(2);
  if (args.length < 2 || args.length > 3) throw Error('Usage: node examples/batch-roi.mjs MANIFEST.json OUTPUT_DIRECTORY [CLI_PATH]');
  const manifest = path.resolve(args[0]), output = path.resolve(args[1]);
  const cli = args[2] ? path.resolve(args[2]) : path.join(root, '_build/js/release/build/cmd/moonnifti/moonnifti.js');
  const cases = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  if (!Array.isArray(cases) || cases.length < 1 || cases.length > 100) throw Error('Manifest must contain 1..100 cases');
  const seen = new Set();
  for (const row of cases) {
    if (!row || typeof row.id !== 'string' || !/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(row.id) || seen.has(row.id)) throw Error('Case IDs must be unique safe identifiers');
    seen.add(row.id);
    if (typeof row.image !== 'string' || typeof row.mask !== 'string' || !Number.isInteger(row.label) || row.label < 0 || row.label > 2147483647) throw Error('Each case requires image, mask and nonnegative integer label');
  }
  // Refuse pre-existing output, including symlinks. Parent must already exist.
  fs.mkdirSync(output);
  const records = [], rows = [['case_id','frame','time_seconds','selected_voxels','minimum','maximum','mean','finite_count','nan_count','positive_infinity_count','negative_infinity_count']];
  const invoke = command => {
    const result = spawnSync(process.execPath, [cli, ...command.map(String)], {encoding:'utf8', timeout:120000, maxBuffer:8*1024*1024});
    if (result.error) throw result.error;
    if (result.status !== 0) throw Error(result.stderr.trim() || `CLI exit ${result.status}`);
    return JSON.parse(result.stdout);
  };
  for (const row of cases) {
    try {
      const image = path.resolve(path.dirname(manifest), row.image);
      const mask = path.resolve(path.dirname(manifest), row.mask);
      const region = invoke(['roi', image, mask, row.label]);
      const crop = invoke(['roi-crop', image, mask, path.join(output, `${row.id}.nii.gz`), row.label]);
      fs.writeFileSync(path.join(output, `${row.id}.json`), JSON.stringify({region,crop},null,2)+'\n', {flag:'wx'});
      for (const frame of region.frames) {
        const s = frame.statistics;
        rows.push([row.id,frame.frame,frame.time_seconds,region.selected_voxels,s.minimum,s.maximum,s.mean,s.finite_count,s.nan_count,s.positive_infinity_count,s.negative_infinity_count]);
      }
      records.push({id:row.id,status:'exported',frames:region.frames.length});
    } catch (error) {
      records.push({id:row.id,status:'rejected',reason:error.message});
    }
  }
  const escape = value => value === null ? '' : '"'+String(value).replaceAll('"','""')+'"';
  fs.writeFileSync(path.join(output,'time-series.csv'), rows.map(row=>row.map(escape).join(',')).join('\n')+'\n', {flag:'wx'});
  const report = {schema:1,selection:'scaled integer labels; prefer-sform; rectangular crop; no extension dropping',cases:records};
  fs.writeFileSync(path.join(output,'report.json'), JSON.stringify(report,null,2)+'\n', {flag:'wx'});
  console.log(JSON.stringify(report,null,2));
  if (records.some(row=>row.status==='rejected')) process.exitCode=2;
}
try {run();} catch (error) {console.error(error.message);process.exitCode=1;}
