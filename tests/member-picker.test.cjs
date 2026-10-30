const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '..', 'private-channel-members.html'), 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
const picker = source.slice(source.indexOf('function getMembershipScopes('), source.indexOf('function renderTeams('));
const search = source.slice(source.indexOf('async function searchUsers('), source.indexOf('let lastResults ='));
const predicate = source.slice(source.indexOf('const canRunMembership ='), source.indexOf('const channelKey ='));
const tick = () => new Promise(resolve => setImmediate(resolve));
const escapeText = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);

async function main() {
  const elements = {}, calls = [];
  const byId = id => elements[id] ??= {
    value: '', innerHTML: '', hidden: false, classList: { toggle() {} },
    querySelectorAll() {
      this.inputs = [...this.innerHTML.matchAll(/data-existing-user="([^"]+)"/g)].map(match => ({
        dataset: { existingUser: match[1] }, handlers: {}, checked: false,
        addEventListener(name, handler) { this.handlers[name] = handler; },
      }));
      return this.inputs;
    },
  };
  const state = {
    connected: true, operation: 'update', busy: false, confirming: false,
    teams: [{ id: 't1', displayName: 'Team1' }], selectedTeams: new Set(['t1']),
    channelsByTeam: new Map([['t1', [{ id: 'c1', displayName: 'Channel1' }, { id: 'c2', displayName: 'Channel2' }]]]),
    selectedChannels: new Set(), users: new Map(), roles: new Map(), existingMembers: new Map(),
    memberPickerKey: '', memberPickerStatus: 'idle', memberPickerRequest: 0, memberPickerError: '', directoryRequest: 0,
  };
  const member = { id: 'u1', displayName: 'Sample Member', email: 'member@contoso.com', role: 'member' };
  const owner = { id: 'u2', displayName: 'Sample Owner', email: 'owner@contoso.com', role: 'owner' };
  const context = {
    state, byId, escapeText, channelKey: (t, c) => `${t}|${c}`, renderUsers() {}, updateSummary() { context.render(); },
    api: async url => { calls.push(url); return { users: [member, owner] }; },
  };
  vm.createContext(context);
  vm.runInContext(picker + search + predicate + ';globalThis.sync=syncMemberPicker;globalThis.render=renderMemberPicker;globalThis.seed=seedCurrentMemberRoles;globalThis.scoped=usersForMembershipScope;globalThis.search=searchUsers;globalThis.canRun=canRunMembership;', context);
  context.sync(); await tick();
  assert.equal(state.memberPickerStatus, 'ready');
  assert.equal(calls.length, 1);
  assert(calls[0].startsWith('/api/membership-users?teamId=t1'));
  assert(!calls[0].includes('channelId'));
  assert.equal(state.existingMembers.size, 2);
  assert(byId('memberPickerList').innerHTML.includes('owner@contoso.com'));
  // Selecting an Owner starts with Owner as the desired role, not Member.
  const ownerInput = byId('memberPickerList').inputs.find(input => input.dataset.existingUser === 'u2');
  ownerInput.checked = true; ownerInput.handlers.change();
  assert.equal(state.roles.get('team|t1|u2'), 'owner');
  assert(context.canRun());
  byId('userSearch').value = 'member@'; await context.search();
  assert.equal(calls.length, 1);
  assert(!byId('memberPickerList').innerHTML.includes('owner@contoso.com'));
  assert(byId('memberPickerList').innerHTML.includes('member@contoso.com'));
  assert(state.users.has('u2')); // Filtering never deselects a member.

  // Private-channel scope never falls back to Team membership or directory search.
  byId('userSearch').value = '';
  state.selectedChannels.add('t1|c1'); context.sync(); await tick();
  assert(calls.at(-1).includes('channelId=c1'));
  assert.equal(state.roles.get('channel|t1|c1|u2'), 'owner');
  assert(!state.roles.has('team|t1|u2'));
  assert.equal(state.existingMembers.get('u2').memberships[0].key, 'channel|t1|c1');

  // Same person may have different roles in two channels.
  context.api = async url => { calls.push(url); return { users: [{ ...owner, role: url.includes('channelId=c1') ? 'owner' : 'member' }] }; };
  state.selectedChannels.add('t1|c2'); context.sync(); await tick();
  assert.equal(state.existingMembers.size, 1);
  assert.equal(state.existingMembers.get('u2').memberships.length, 2);
  assert.equal(state.roles.get('channel|t1|c1|u2'), 'owner');
  assert.equal(state.roles.get('channel|t1|c2|u2'), 'member');
  assert.equal(context.scoped('t1', 'c1').length, 1);
  assert.equal(context.scoped('t1', '').length, 0);

  // Ignore the response of a previous scope after switching channels quickly.
  let resolveOld;
  context.api = async url => {
    if (url.includes('channelId=c1')) return new Promise(resolve => { resolveOld = resolve; });
    return { users: [member] };
  };
  state.selectedChannels = new Set(['t1|c1']); context.sync();
  state.selectedChannels = new Set(['t1|c2']); context.sync(); await tick();
  resolveOld({ users: [owner] }); await tick();
  assert(state.existingMembers.has('u1'));
  assert(!state.existingMembers.has('u2'));
  assert.equal(state.users.size, 0);
  assert.equal(state.roles.size, 0);

  // Partial failures show available members, disable execution, and never search the directory.
  state.selectedChannels = new Set(['t1|c1', 't1|c2']);
  context.api = async url => {
    calls.push(url);
    if (url.includes('channelId=c1')) throw new Error('Mock access denied');
    return { users: [member] };
  };
  context.sync(); await tick();
  assert.equal(state.memberPickerStatus, 'error');
  assert(state.existingMembers.has('u1'));
  assert(!context.canRun());
  assert(byId('memberPickerList').innerHTML.includes('Mock access denied'));
  state.operation = 'remove'; byId('userSearch').value = 'm'; await context.search();
  assert(!calls.some(url => url.startsWith('/api/users')));

  // Add mode alone uses directory search; ignore a response after changing mode.
  let resolveDirectory;
  context.api = async url => { calls.push(url); return new Promise(resolve => { resolveDirectory = resolve; }); };
  state.operation = 'add'; byId('userSearch').value = 'sample';
  const pendingSearch = context.search();
  assert(calls.at(-1).startsWith('/api/users?q='));
  state.operation = 'remove';
  byId('userSuggestions').innerHTML = ''; // Mode-change handler clears directory suggestions.
  resolveDirectory({ users: [owner] }); await pendingSearch;
  assert.equal(byId('userSuggestions').innerHTML, '');
  console.log('PASS: scoped member loading, current-role selection, local filtering, no directory fallback, multi-channel roles, stale-response protection, selection pruning, partial failures and add-only directory search.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
