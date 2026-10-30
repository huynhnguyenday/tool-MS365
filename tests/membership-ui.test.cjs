const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const html = fs.readFileSync(path.join(__dirname, '..', 'private-channel-members.html'), 'utf8');
const source = html.match(/<script>([\s\S]*?)<\/script>/)[1];
new vm.Script(source);
const run = source.slice(source.indexOf('async function runMembershipOperation()'), source.indexOf('byId("addButton").addEventListener'));
const helpers = source.slice(source.indexOf('let lastResults ='), source.indexOf('function renderResults('));
const scopeHelper = source.slice(source.indexOf('function usersForMembershipScope('), source.indexOf('function seedCurrentMemberRoles('));
const operationLabels = { add: 'Add', update: 'Update', remove: 'Remove' };
const escapeText = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);

async function runScenario(operation, { oldServer = false, cancel = false, declineParent = false, scopedOnly = false } = {}) {
  const users = [{ id: 'u1', displayName: 'Sample 1', userPrincipalName: 'sample1@contoso.com' }, { id: 'u2', displayName: 'Sample 2', userPrincipalName: 'sample2@contoso.com' }];
  const state = {
    operation, users: new Map(users.map(u => [u.id, u])), selectedTeams: new Set(['t1', 't2']),
    teams: [{ id: 't1', displayName: 'Team1' }, { id: 't2', displayName: 'Team2' }],
    channelsByTeam: new Map([['t1', [{ id: 'c1', displayName: 'Channel1' }]], ['t2', []]]),
    selectedChannels: new Set(['t1|c1']), roles: new Map([['t1|c1|u2', 'owner']]),
    existingMembers: new Map(users.map(user => [user.id, { ...user, memberships: [{ key: 'channel|t1|c1', teamId: 't1', role: 'member' }, { key: 'team|t2', teamId: 't2', role: 'member' }].filter(membership => !scopedOnly || (user.id === 'u1' ? membership.teamId === 't1' : membership.teamId === 't2')) }])),
  };
  let modalCount = 0, results;
  const calls = [], order = [], notices = [], dialogs = [], elements = {};
  const context = {
    state, operationLabels, Date, escapeText,
    channelKey: (t, c) => `${t}|${c}`, channelRoleKey: (t, c, u) => `${t}|${c}|${u}`, teamRoleKey: (t, u) => `${t}|${u}`,
    byId: id => elements[id] ??= {}, setBusy() {}, updateSummary() {}, showResults() {}, syncMemberPicker() {},
    renderResults: rows => { results = Array.from(rows); },
    notify: (text, type, rows) => { notices.push({ text, type, rows }); order.push('notify'); },
    askInAppModal: async options => {
      dialogs.push(options);
      modalCount++;
      // A later UI role change must not change the confirmed snapshot.
      state.roles.set('t1|c1|u2', 'member');
      return !cancel && !(declineParent && modalCount > 1);
    },
    api: async (url, options) => {
      if (url === '/api/status') return oldServer ? {} : { membershipOperations: ['add', 'remove', 'update'] };
      const body = JSON.parse(options.body);
      calls.push(body);
      if (body.validateOnly) {
        return operation === 'add' && body.teamId === 't1' ? { needsTeamConfirmation: true, missingUsers: users } : { validated: true };
      }
      order.push('execute');
      assert.equal(body.operation, operation);
      assert.equal(body.confirmed, true);
      assert.equal(body.users.length, 1);
      assert.equal(body.assignments.length, body.teamId === 't1' ? 1 : 0);
      assert.equal(body.teamAssignments.length, body.teamId === 't1' ? 0 : 1);
      if (operation !== 'add') assert.equal(body.addMissingToTeam, false);
      if (body.teamId === 't1' && body.users[0].id === 'u1') {
        const error = new Error('Mock Graph failure');
        error.trace = [{ command: 'GET sample', status: 'error', detail: error.message }];
        throw error;
      }
      return {
        results: [{ user: body.users[0].userPrincipalName, channel: 'Sample scope', status: operation === 'remove' ? 'Removed' : operation === 'update' ? 'Updated' : 'Added' }],
        trace: [{ sequence: 1, command: operation === 'remove' ? 'DELETE sample' : 'PATCH sample', status: 'success' }],
      };
    },
  };
  vm.createContext(context);
  vm.runInContext(scopeHelper + helpers + run + ';globalThis.run=runMembershipOperation;globalThis.renderTrace=renderTrace;globalThis.resultKind=resultKind;', context);
  await context.run();
  if (oldServer || cancel) {
    assert.equal(calls.length, 0);
    if (oldServer) assert.equal(dialogs.length, 0);
    return;
  }
  const writes = calls.filter(call => !call.validateOnly);
  assert.equal(writes.length, declineParent || scopedOnly ? 2 : 4);
  if (declineParent) assert(writes.every(call => call.teamId === 't2'));
  else {
    assert.equal(results.filter(row => row.status === 'Error').length, 1);
    assert(results.some(row => row.channel.startsWith('Team2') && row.user === 'sample2@contoso.com'));
    assert.equal(notices[0].rows[0].trace[0].command, 'GET sample');
    assert(order.indexOf('notify') < order.lastIndexOf('execute'));
    assert.equal(notices.at(-1).type, 'warning');
    if (!scopedOnly) assert.equal(writes.find(call => call.teamId === 't1' && call.users[0].id === 'u2').assignments[0].role, 'owner');
    else assert(writes.every(call => call.teamId === (call.users[0].id === 'u1' ? 't1' : 't2')));
    if (operation === 'remove') assert(results.every(row => row.role === null));
  }
  assert.equal(modalCount, operation === 'add' ? 2 : 1);
  assert.equal(dialogs[0].danger, operation === 'remove');
  assert.equal(context.resultKind({ status: 'Removed' }), 'success');
  assert.equal(context.resultKind({ status: 'NotMember' }), 'error');
  const trace = context.renderTrace([{ command: '<script>x</script>', detail: '<img>', status: 'error', time: new Date().toISOString() }]);
  assert(!trace.includes('<script>'));
  assert(trace.includes('&lt;img&gt;'));
}

function testModalAndRendering() {
  const elements = {};
  const shell = { inert: false };
  const document = { activeElement: { isConnected: true, focus() {} }, querySelector: () => shell, addEventListener() {}, removeEventListener() {} };
  const byId = id => elements[id] ??= {
    classes: new Set(), handlers: {}, isConnected: true,
    classList: { add(name) { byId(id).classes.add(name); }, remove(name) { byId(id).classes.delete(name); }, toggle(name, on) { on ? byId(id).classes.add(name) : byId(id).classes.delete(name); } },
    focus() { document.activeElement = this; }, setAttribute() {}, querySelectorAll: () => [],
    addEventListener(name, handler) { this.handlers[name] = handler; }, removeEventListener(name) { delete this.handlers[name]; },
    showModal() { this.open = true; },
  };
  const modal = source.slice(source.indexOf('function askInAppModal('), source.indexOf('const taskbarButton ='));
  const results = source.slice(source.indexOf('let lastResults ='), source.indexOf('byId("resultFilters").addEventListener'));
  const context = { byId, document, escapeText, Date };
  vm.createContext(context);
  vm.runInContext(modal + results + ';globalThis.ask=askInAppModal;globalThis.show=showResults;', context);
  const promise = context.ask({ title: 'Remove', items: [], acceptText: 'Remove', danger: true });
  assert(shell.inert);
  assert.equal(document.activeElement, byId('teamModalCancel'));
  assert(byId('teamModalAccept').classes.has('danger'));
  byId('teamModalCancel').handlers.click();
  assert.equal(shell.inert, false);
  context.show([{ channel: 'Sample', user: 'sample@contoso.com', status: 'Removed', trace: [{ command: 'DELETE sample', time: new Date().toISOString(), status: 'success' }] }], true);
  assert(byId('resultDialog').open);
  assert(byId('resultReset').hidden);
  assert(byId('resultList').innerHTML.includes('DELETE sample'));
  return promise.then(accepted => assert.equal(accepted, false));
}

async function testDoubleClick() {
  const start = source.indexOf('byId("addButton").addEventListener');
  const listener = source.slice(start, source.indexOf('api("/api/status")', start));
  let click, finish, runs = 0;
  const element = { addEventListener: (_, handler) => { click = handler; } };
  const state = { busy: false, confirming: false };
  const context = {
    state, byId: () => element, canRunMembership: () => !state.confirming,
    runMembershipOperation: () => { runs++; return new Promise(resolve => { finish = resolve; }); },
    notify() {}, updateSummary() {}, updateClearSelectionButtons() {},
  };
  vm.createContext(context);
  vm.runInContext(listener, context);
  click(); click();
  assert.equal(runs, 1);
  assert(state.confirming);
  finish();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(state.confirming, false);
}

function testClearSelections() {
  const code = source.slice(source.indexOf('function updateClearSelectionButtons('), source.indexOf('function getMembershipScopes('));
  const elements = {};
  const state = { busy: false, confirming: false, users: new Map([['u1', {}]]), roles: new Map([['role', 'owner']]), selectedTeams: new Set(['t1']), selectedChannels: new Set(['t1|c1']), expandedChannels: new Set(['t1']), activeTeamId: 't1', directoryRequest: 0 };
  const context = { state, byId: id => elements[id] ??= { value: 'sample' }, searchTimer: null, clearTimeout() {}, renderTeams() {}, renderChannels() {}, renderUsers() {}, updateSummary() {} };
  vm.createContext(context);
  vm.runInContext(code + ';globalThis.update=updateClearSelectionButtons;globalThis.clearUsers=clearUserSelection;globalThis.clearTeams=clearTeamSelection;', context);
  context.update();
  assert.equal(elements.clearUserSelection.disabled, false);
  assert.equal(elements.clearTeamSelection.disabled, false);
  context.clearUsers(); context.update();
  assert.equal(state.users.size, 0);
  assert.equal(state.roles.size, 0);
  assert.equal(state.selectedTeams.size, 1);
  assert.equal(elements.userSearch.value, '');
  assert.equal(elements.userSuggestions.innerHTML, '');
  assert.equal(elements.clearUserSelection.disabled, true);
  state.users.set('u1', {});
  state.busy = true; context.clearUsers(); context.clearTeams(); context.update();
  assert.equal(state.users.size, 1);
  assert.equal(state.selectedTeams.size, 1);
  assert.equal(elements.clearUserSelection.disabled, true);
  assert.equal(elements.clearTeamSelection.disabled, true);
  state.busy = false; state.confirming = true; context.clearTeams();
  assert.equal(state.selectedTeams.size, 1);
  state.confirming = false; context.clearTeams(); context.update();
  assert.equal(state.selectedTeams.size, 0);
  assert.equal(state.selectedChannels.size, 0);
  assert.equal(state.expandedChannels.size, 0);
  assert.equal(state.activeTeamId, '');
  assert.equal(state.users.size, 1);
  assert.equal(elements.clearTeamSelection.disabled, true);
}

(async () => {
  for (const operation of ['add', 'remove', 'update']) {
    await runScenario(operation);
    await runScenario(operation, { cancel: true });
    if (operation !== 'add') {
      await runScenario(operation, { oldServer: true });
      await runScenario(operation, { scopedOnly: true });
    }
  }
  await runScenario('add', { declineParent: true });
  await testModalAndRendering();
  await testDoubleClick();
  testClearSelections();
  const css = fs.readFileSync(path.join(__dirname, '..', 'private-channel-members.css'), 'utf8');
  assert.equal((css.match(/{/g) || []).length, (css.match(/}/g) || []).length);
  assert(css.includes('.primary.danger'));
  const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
  assert.equal(new Set(ids).size, ids.length);
  console.log('PASS: JavaScript syntax; add/remove/update UI, scoped per-user requests, confirmation/cancel, old-server protection, duplicate-click guard, role snapshot, failure isolation, notifications, escaped traces, modal rendering, CSS structure and unique HTML IDs.');
})().catch(error => { console.error(error); process.exitCode = 1; });
