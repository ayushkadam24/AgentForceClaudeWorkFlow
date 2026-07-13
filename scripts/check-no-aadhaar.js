#!/usr/bin/env node
/* No-Aadhaar guard for STAGED content (Annexure C1.2). Run: node scripts/check-no-aadhaar.js
 * Closes the gap the PreToolUse Write-guard cannot: content written via Bash redirects/tee/sed
 * never passes through the Write tool, so it is only caught here — at `git commit` and in CI.
 * Scans the staged (index) version of every added/copied/modified text file for a 12-digit run
 * (Aadhaar shape, incl. 4-4-4 grouping). Exit 0 = clean, 1 = block the commit. */
const { execFileSync } = require('child_process');
const git = (args) => execFileSync('git', args, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });

let staged;
try {
  staged = git(['diff', '--cached', '--name-only', '--diff-filter=ACM'])
    .split('\n').map(s => s.trim()).filter(Boolean);
} catch (e) {
  // No git / not a repo — don't wedge the commit; the Write-guard + health-check still cover source.
  console.error('check-no-aadhaar: git unavailable (' + e.message + ') — skipping.');
  process.exit(0);
}

const TEXT = /\.(xml|js|ts|cls|json|csv|html|css|apex|md|txt|soql|sh|yml|yaml)$/i;
// Never read the answer key; static resources may legitimately carry long digit blobs (fixtures/images).
const SKIP = (p) => /answer-key-intentional-gaps/i.test(p) || /(^|\/)staticresources\//i.test(p);

const hits = [];
for (const p of staged) {
  if (!TEXT.test(p) || SKIP(p)) continue;
  let content;
  try { content = git(['show', ':' + p]); } catch { continue; } // deleted-then-restaged etc.
  content.split(/\r?\n/).forEach((ln, i) => {
    const digits = ln.replace(/[ \-]/g, '');
    if (/(?<!\d)\d{12}(?!\d)/.test(digits)) hits.push(p + ':' + (i + 1));
  });
}

if (hits.length) {
  console.error('COMMIT BLOCKED — possible Aadhaar-like 12-digit value in STAGED content (Annexure C1.2):');
  hits.forEach(h => console.error('  ' + h));
  console.error('No Aadhaar anywhere — code, metadata, seed/test data, logs, or free text.');
  console.error('Use obviously-fake short identifiers. If this is a false positive, split the digit run.');
  process.exit(1);
}
console.log('check-no-aadhaar: staged content clean (' + staged.length + ' file(s) checked).');
process.exit(0);
