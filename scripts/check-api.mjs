import assert from 'node:assert/strict';
import fs from 'node:fs';
const api = fs.readFileSync(new URL('../pkg.generated.mbti', import.meta.url), 'utf8');
for (const name of ['Image','Affine']) {
  const declaration = api.match(new RegExp(`pub struct ${name} \\{([^}]+)\\}`));
  assert.ok(declaration, `missing ${name} declaration`);
  assert.match(declaration[1], /private fields/);
  assert.doesNotMatch(declaration[1], /(?:FixedArray|Bytes|Array)\[/);
}
console.log('Image/Affine storage is private across package boundaries');
