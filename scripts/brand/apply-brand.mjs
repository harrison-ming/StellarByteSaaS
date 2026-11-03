#!/usr/bin/env node
// StellarByte build-time brand replacement (L2, see docs/redeploy-spec.md 3.1 / 3.2).
//
// Usage:
//   node scripts/brand/apply-brand.mjs           apply in place (Docker build, before `pnpm run build`)
//   node scripts/brand/apply-brand.mjs --check   dry run: report per-rule hit counts, run every scan
//                                                on the would-be result, write nothing
//   add --verbose to list every residual / allowlisted hit
//
// Guarantees (each one fails the run with exit code 1):
//   1. every rule hits at least `min` times (a rule that silently stops matching
//      after an upstream copy change breaks the build instead of shipping "Postiz");
//   2. after replacement, no user-visible "Postiz" remains outside allowlist.txt;
//   3. no fabricated social proof ("20,000+" style counts) remains;
//   4. every Tailwind arbitrary-value class using a deprecated upstream colour is
//      re-pointed in apps/frontend/src/app/brand-overrides.scss.
// Only values / user-visible strings are rewritten: locale keys, package names,
// env variable names, header names and class names are never touched.
// Zero dependencies on purpose: it runs before `pnpm install` would matter.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const MARKER = path.join(ROOT, '.brand-applied');
const args = new Set(process.argv.slice(2));
const CHECK = args.has('--check');
const VERBOSE = args.has('--verbose');
const SKIP_DIRS = new Set(['node_modules', '.git', '.next', 'dist', '.nx', 'coverage']);

const manifest = JSON.parse(fs.readFileSync(path.join(HERE, 'manifest.json'), 'utf8'));
const errors = [];
const rel = (p) => path.relative(ROOT, p).split(path.sep).join('/');

// ---------- tiny glob (supports **, *, ?, {a,b}) ----------
function globToRegex(glob) {
  let re = '';
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === '*') {
      if (glob[i + 1] === '*') {
        i++;
        if (glob[i + 1] === '/') {
          i++;
          re += '(?:.*/)?';
        } else re += '.*';
      } else re += '[^/]*';
    } else if (c === '?') re += '[^/]';
    else if (c === '{') {
      const end = glob.indexOf('}', i);
      re += '(?:' + glob.slice(i + 1, end).split(',').map(escapeRe).join('|') + ')';
      i = end;
    } else re += escapeRe(c);
  }
  return new RegExp('^' + re + '$');
}
function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
}
const walkCache = new Map();
function walk(dir) {
  if (walkCache.has(dir)) return walkCache.get(dir);
  const out = [];
  const stack = [dir];
  while (stack.length) {
    const d = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(d, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      if (SKIP_DIRS.has(e.name)) continue;
      const full = path.join(d, e.name);
      if (e.isDirectory()) stack.push(full);
      else if (e.isFile()) out.push(rel(full));
    }
  }
  out.sort();
  walkCache.set(dir, out);
  return out;
}
function expand(globs) {
  const result = new Set();
  for (const g of [].concat(globs)) {
    if (!/[*?{]/.test(g)) {
      if (fs.existsSync(path.join(ROOT, g))) result.add(g);
      continue;
    }
    const parts = g.split('/');
    const base = parts.slice(0, parts.findIndex((p) => /[*?{]/.test(p))).join('/');
    const re = globToRegex(g);
    for (const f of walk(path.join(ROOT, base))) if (re.test(f)) result.add(f);
  }
  return [...result].sort();
}

// ---------- virtual file system (check mode never writes) ----------
const vfs = new Map();
const dirty = new Set();
const read = (f) => {
  if (!vfs.has(f)) vfs.set(f, fs.readFileSync(path.join(ROOT, f), 'utf8'));
  return vfs.get(f);
};
const write = (f, s) => {
  if (read(f) !== s) {
    vfs.set(f, s);
    dirty.add(f);
  }
};
function makeMatcher(rule) {
  if (rule.regex) return new RegExp(rule.find, 'g' + (rule.flags || ''));
  return new RegExp(escapeRe(rule.find), 'g');
}
function countAndReplace(text, rule) {
  const re = makeMatcher(rule);
  let hits = 0;
  const single = rule.regex ? new RegExp(rule.find, rule.flags || '') : null;
  const out = text.replace(re, (match) => {
    hits++;
    // regex rules may use $1-style backrefs; literal rules are inserted verbatim
    return single ? match.replace(single, rule.replace) : rule.replace;
  });
  return { out, hits };
}

if (fs.existsSync(MARKER)) {
  console.error(
    `[apply-brand] ${rel(MARKER)} exists: this tree is already branded. Run on a clean checkout (git stash / git checkout .).`
  );
  process.exit(1);
}

// ---------- 1. source rules ----------
const report = [];
for (const rule of manifest.rules) {
  const files = expand(rule.files);
  let hits = 0;
  const perFile = [];
  for (const f of files) {
    const r = countAndReplace(read(f), rule);
    if (r.hits) {
      hits += r.hits;
      perFile.push(`${f}:${r.hits}`);
      write(f, r.out);
    }
  }
  const ok = hits >= (rule.min ?? 1) && hits > 0;
  report.push({ id: rule.id, hits, min: rule.min ?? 1, ok, files: perFile });
  if (!ok) errors.push(`rule "${rule.id}" hit ${hits} time(s), expected >= ${rule.min ?? 1} (globs: ${[].concat(rule.files).join(', ')})`);
}

// ---------- 2. allowlist (parsed first: locale keys listed here are never rewritten) ----------
// Format (one per line, "#" starts a comment, reason is mandatory):
//   <file glob | locale:<key>> | <substring or *> | <reason>
const allow = fs
  .readFileSync(path.join(HERE, 'allowlist.txt'), 'utf8')
  .split('\n')
  .map((l) => l.trim())
  .filter((l) => l && !l.startsWith('#'))
  .map((l, i) => {
    const [target, needle, reason] = l.split('|').map((s) => s?.trim());
    if (!target || !needle || !reason) errors.push(`allowlist.txt entry ${i + 1} malformed (need target | needle | reason): ${l}`);
    return {
      target,
      needle,
      reason,
      re: target && !target.startsWith('locale:') ? globToRegex(target) : null,
      used: 0,
    };
  });
function allowed(kind, where, line) {
  for (const a of allow) {
    const targetOk = kind === 'locale' ? a.target === `locale:${where}` : a.re && a.re.test(where);
    if (targetOk && (a.needle === '*' || line.includes(a.needle))) {
      a.used++;
      return a;
    }
  }
  return null;
}

// ---------- 3. locale rules (values only, keys and file layout untouched) ----------
const L = manifest.locales;
const localeFiles = expand(L.files);
if (localeFiles.length < L.expectFiles) errors.push(`locales: found ${localeFiles.length} files, expected ${L.expectFiles}`);
const PAIR = /"((?:[^"\\]|\\.)*)"(\s*:\s*)"((?:[^"\\]|\\.)*)"/g;
const skipKeys = new Set(allow.filter((a) => a.target?.startsWith('locale:')).map((a) => a.target.slice(7)));
const localeHits = Object.fromEntries(L.rules.map((r) => [r.id, 0]));
for (const f of localeFiles) {
  const text = read(f);
  const out = text.replace(PAIR, (whole, key, sep, value) => {
    if (L.overrideKeys[key] !== undefined) {
      localeHits.__override = (localeHits.__override || 0) + 1;
      return `"${key}"${sep}${JSON.stringify(L.overrideKeys[key])}`;
    }
    if (skipKeys.has(key)) return whole;
    let v = value;
    for (const r of L.rules) {
      const res = countAndReplace(v, r);
      localeHits[r.id] += res.hits;
      v = res.out;
    }
    return `"${key}"${sep}"${v}"`;
  });
  write(f, out);
}
for (const r of L.rules) {
  const ok = localeHits[r.id] >= (r.min ?? 1) && localeHits[r.id] > 0;
  report.push({ id: `locale:${r.id}`, hits: localeHits[r.id], min: r.min ?? 1, ok, files: [] });
  if (!ok) errors.push(`locale rule "${r.id}" hit ${localeHits[r.id]} time(s), expected >= ${r.min ?? 1}`);
}
{
  const n = localeHits.__override || 0;
  const min = Object.keys(L.overrideKeys).length * (L.overrideMinPerKey ?? 1);
  const ok = n >= min;
  report.push({ id: 'locale:override-keys', hits: n, min, ok, files: [] });
  if (!ok) errors.push(`locale override keys hit ${n} time(s), expected >= ${min}`);
}

// ---------- 4. residual scan (on post-replacement content) ----------
const R = manifest.residual;
const residualRe = new RegExp(R.pattern);
const commentRe = /^\s*(\/\/|\*|\/\*|\{\s*\/\*)/;
const residual = [];
const allowedHits = [];
for (const f of expand(R.files)) {
  if (localeFiles.includes(f)) continue;
  const lines = read(f).split('\n');
  lines.forEach((line, i) => {
    if (!residualRe.test(line) || commentRe.test(line)) return;
    const a = allowed('file', f, line);
    (a ? allowedHits : residual).push(`${f}:${i + 1}: ${line.trim().slice(0, 140)}${a ? `  [allow: ${a.reason}]` : ''}`);
  });
}
for (const f of localeFiles) {
  for (const m of read(f).matchAll(PAIR)) {
    const [, key, , value] = m;
    if (!residualRe.test(value)) continue;
    const a = allowed('locale', key, value);
    (a ? allowedHits : residual).push(`${f} [${key}]: ${value.slice(0, 120)}${a ? `  [allow: ${a.reason}]` : ''}`);
  }
}
if (residual.length) errors.push(`residual scan: ${residual.length} user-visible "Postiz" hit(s) not in allowlist.txt`);

// ---------- 5. honesty scan: fabricated social proof ----------
const H = manifest.honesty;
const honestyRe = new RegExp(H.pattern, 'i');
const honesty = [];
for (const f of [...expand(H.files), ...localeFiles]) {
  read(f)
    .split('\n')
    .forEach((line, i) => {
      if (honestyRe.test(line) && !commentRe.test(line) && !allowed('file', f, line)) honesty.push(`${f}:${i + 1}: ${line.trim().slice(0, 140)}`);
    });
}
if (honesty.length) errors.push(`honesty scan: ${honesty.length} social-proof claim(s) found`);

// ---------- 6. deprecated colour classes must be covered by brand-overrides.scss ----------
const C = manifest.colors;
const overrides = read(C.overridesFile);
const classRe = new RegExp(`[A-Za-z0-9:!_-]*\\[#(?:${C.deprecated.join('|')})\\](?:\\/\\d+)?`, 'gi');
const uncovered = new Map();
for (const f of expand(C.files)) {
  if (allowed('file', f, '[color]')) continue;
  for (const m of read(f).matchAll(classRe)) {
    const cls = m[0];
    const escaped = '.' + cls.replace(/([[\]#/:!.])/g, '\\$1');
    if (!overrides.includes(escaped + ' ') && !overrides.includes(escaped + ':')) {
      if (!uncovered.has(cls)) uncovered.set(cls, f);
    }
  }
}
if (uncovered.size) errors.push(`colors: ${uncovered.size} deprecated-colour class(es) not re-pointed in ${C.overridesFile}`);

// ---------- output ----------
console.log(`[apply-brand] mode=${CHECK ? 'check (dry run)' : 'apply'} root=${ROOT}`);
console.log('rule'.padEnd(44) + 'hits'.padStart(6) + 'min'.padStart(6) + '  status');
for (const r of report) {
  console.log(r.id.padEnd(44) + String(r.hits).padStart(6) + String(r.min).padStart(6) + '  ' + (r.ok ? 'ok' : 'FAIL'));
  if (VERBOSE) r.files.forEach((x) => console.log('    ' + x));
}
console.log(
  `rules: ${report.length} (${report.filter((r) => r.ok).length} ok) | files changed: ${dirty.size} | residual: ${residual.length} | allowlisted hits: ${allowedHits.length} | honesty: ${honesty.length} | uncovered colours: ${uncovered.size}`
);
const unused = allow.filter((a) => !a.used);
if (unused.length) console.log(`warning: ${unused.length} allowlist entr${unused.length === 1 ? 'y' : 'ies'} matched nothing: ${unused.map((a) => a.target).join(', ')}`);
if (residual.length) console.log('residual hits:\n  ' + residual.join('\n  '));
if (VERBOSE && allowedHits.length) console.log('allowlisted hits:\n  ' + allowedHits.join('\n  '));
if (honesty.length) console.log('honesty hits:\n  ' + honesty.join('\n  '));
if (uncovered.size) console.log('uncovered colour classes:\n  ' + [...uncovered].map(([c, f]) => `${c}  (${f})`).join('\n  '));

if (errors.length) {
  console.error('\n[apply-brand] FAILED:\n  - ' + errors.join('\n  - '));
  process.exit(1);
}
if (!CHECK) {
  for (const f of dirty) fs.writeFileSync(path.join(ROOT, f), vfs.get(f));
  fs.writeFileSync(MARKER, `applied ${new Date().toISOString()}\n`);
  console.log(`[apply-brand] wrote ${dirty.size} file(s); marker ${rel(MARKER)}`);
} else {
  console.log('[apply-brand] check passed (no files written)');
}
