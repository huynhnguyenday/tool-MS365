const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const html = fs.readFileSync(path.join(__dirname, '..', 'private-channel-members.html'), 'utf8');
const source = html.match(/<script>([\s\S]*?)<\/script>/)[1];
new vm.Script(source);
const feature = source.slice(source.indexOf('function parseReleaseNotes('), source.indexOf('async function checkForUpdates('));
const escapeText = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
const tick = () => new Promise(resolve => setImmediate(resolve));
const localMarkdown = '## Chưa phát hành\n- Pending work\n## 1.1.0 — 2026-10-31\n### Sửa lỗi\n- Local fix `safe`\n## 1.0.0 — 2026-10-26\n- Older fix\n## Cách ghi\n- Not a release';
const remoteMarkdown = '## 1.10.0 — 2026-11-02\n### Tính năng mới\n- <img src=x onerror=alert(1)>\n  continued\n## 1.2.0 — 2026-11-01\n- New fix\n## 1.1.0 — 2026-10-31\n- Remote duplicate';
const local = { currentVersion: '1.1.0', localMarkdown, remoteMarkdown: '', warning: '' };
const remote = { ...local, remoteMarkdown };
const elements = {}, calls = [];
let focusCount = 0, closeCount = 0;
const byId = id => elements[id] ||= {
  open: false, innerHTML: '', textContent: '', attrs: {}, handlers: {},
  setAttribute(name, value) { this.attrs[name] = value; },
  addEventListener(name, callback) { this.handlers[name] = callback; },
  showModal() { this.open = true; },
  close() { this.open = false; this.handlers.close?.(); },
};
const context = { byId, escapeText, closeTaskPanel() { closeCount++; }, taskbarButton: { focus() { focusCount++; } }, api: async url => { calls.push(url); return local; } };
vm.createContext(context);
vm.runInContext(feature + '\nglobalThis.parse=parseReleaseNotes;globalThis.markup=releaseNotesMarkup;globalThis.openNotes=openReleaseNotes;globalThis.setNew=value=>releaseUpdateAvailable=value;', context);

async function main() {
  assert.equal(context.parse(localMarkdown).length, 2);
  const cards = context.markup(remote);
  assert(cards.indexOf('v1.10.0') < cards.indexOf('v1.2.0'));
  assert.equal((cards.match(/v1\.1\.0</g) || []).length, 1);
  assert(cards.includes('Đang sử dụng'));
  assert(cards.includes('Bản mới'));
  assert(cards.includes('<code>safe</code>'));
  assert(cards.includes('&lt;img'));
  assert(!cards.includes('<img'));
  assert(!cards.includes('Pending work'));
  assert(!cards.includes('Not a release'));
  assert(!cards.includes('Remote duplicate'));
  const planned = context.markup({ ...local, localMarkdown: '## 1.1.1 — Chưa phát hành\n- Planned feature\n' + localMarkdown });
  assert(planned.includes('v1.1.1'));
  assert(planned.includes('Sắp phát hành'));
  assert(planned.includes('Đang sử dụng'));
  assert(!planned.includes('>Bản mới<'));
  const plannedRelease = context.parse('## 1.1.1 — Chưa phát hành\n- Planned feature')[0];
  assert.equal(plannedRelease.pending, true);
  assert(context.markup({ ...local, localMarkdown: '' }).includes('Chưa có lịch sử'));
  const actual = fs.readFileSync(path.join(__dirname, '..', 'CHANGELOG.md'), 'utf8');
  assert(context.parse(actual).some(release => release.version === '1.1.0'));

  await context.openNotes();
  assert.equal(calls.length, 1); // Offline/local read does not start a GitHub request.
  assert.equal(calls[0], '/api/release-notes');
  assert.equal(closeCount, 1);
  assert(byId('releaseNotesDialog').open);
  assert(byId('releaseNotesList').innerHTML.includes('Local fix'));
  assert.equal(byId('releaseNotesList').attrs['aria-busy'], 'false');
  byId('releaseNotesClose').handlers.click();
  assert.equal(focusCount, 1);
  // Reopening reads updated local notes even when VERSION is unchanged.
  context.api = async (url, options) => {
    assert.equal(options.cache, 'no-store');
    return { ...local, localMarkdown: localMarkdown.replace('Local fix', 'Changed after first open') };
  };
  await context.openNotes();
  assert(byId('releaseNotesList').innerHTML.includes('Changed after first open'));
  assert(!byId('releaseNotesList').innerHTML.includes('Local fix'));
  byId('releaseNotesDialog').close();

  context.setNew(true);
  let finishRemote;
  context.api = async url => {
    calls.push(url);
    if (url.includes('?remote=1')) return new Promise(resolve => { finishRemote = resolve; });
    return local;
  };
  const pending = context.openNotes(); await tick();
  assert(byId('releaseNotesList').innerHTML.includes('Local fix')); // Visible while network is pending.
  finishRemote({ ...remote, warning: 'Offline fallback' }); await pending;
  assert(byId('releaseNotesList').innerHTML.includes('v1.10.0'));
  assert.equal(byId('releaseNotesStatus').textContent, 'Offline fallback');
  byId('releaseNotesDialog').close();

  const stale = context.openNotes(); await tick();
  const finishOld = finishRemote;
  byId('releaseNotesDialog').close();
  context.setNew(false);
  context.api = async () => local;
  await context.openNotes();
  finishOld(remote); await stale;
  assert(!byId('releaseNotesList').innerHTML.includes('v1.10.0')); // Closed/reopened dialog ignores old responses.
  byId('releaseNotesDialog').close();

  context.api = async () => { throw new Error('Local server unavailable'); };
  await context.openNotes();
  assert(byId('releaseNotesStatus').textContent.includes('CHANGELOG.md'));
  assert.equal(byId('releaseNotesList').attrs['aria-busy'], 'false');
  console.log('PASS: release parsing, numeric ordering, draft exclusion, safe rendering, local precedence, offline reads, remote loading, fallback notices, close/focus, stale-response protection and error recovery.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
