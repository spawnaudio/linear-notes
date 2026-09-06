import { build } from 'esbuild';
import { copyFile, mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
const outdir = '../Sources/LinearNotes/Resources/Editor';
await mkdir(outdir, { recursive: true });
await build({ entryPoints: ['src/editor.js'], bundle: true, outfile: `${outdir}/editor.js`, minify: true, target: 'safari17', legalComments: 'external' });
await Promise.all(['index.html', 'editor.css'].map(name => copyFile(`src/${name}`, `${outdir}/${name}`)));
const lock = JSON.parse(await readFile('package-lock.json', 'utf8'));
const licenses = [];
for (const [path, metadata] of Object.entries(lock.packages)) {
  if (!path || metadata.dev) continue;
  const license = (await readdir(path)).find(name => /^licen[sc]e(?:\.|$)/i.test(name));
  if (license) licenses.push(`${path.replace(/^node_modules\//, '')} ${metadata.version}\n${await readFile(`${path}/${license}`, 'utf8')}`);
}
await writeFile(`${outdir}/THIRD_PARTY_LICENSES.txt`, licenses.join('\n\n------------------------------------------------------------\n\n'));
