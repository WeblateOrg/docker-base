// Copyright © Michal Čihař <michal@weblate.org>
//
// SPDX-License-Identifier: MIT

const assert = require('node:assert/strict');
const {test} = require('node:test');
const {nextVersion, basePin, prepare, finalize} = require('../.github/scripts/release.cjs');

const sourceSha = 'a'.repeat(40);
const digest = `sha256:${'b'.repeat(64)}`;
const baseImage = `weblate/base:2026.45.0@${digest}`;
const version = 'v2026.45.1';
const now = new Date('2026-11-04T12:00:00Z');
const refs = (...tags) => tags.map(tag => ({ref: `refs/tags/${tag}`}));
const missing = () => Object.assign(new Error('Not found'), {status: 404});

function fixture() {
  const calls = [];
  const outputs = {};
  const state = {ref: null, tag: null, release: null, summary: null};
  const context = {repo: {owner: 'WeblateOrg', repo: 'docker-dev'}, sha: sourceSha,
    eventName: 'workflow_dispatch', payload: {before: 'c'.repeat(40)}};
  const core = {
    setOutput: (key, value) => {outputs[key] = value;},
    info() {},
    summary: {
      addHeading() {return this;},
      addTable(rows) {state.summary = rows; return this;},
      async write() {},
    },
  };
  const github = {rest: {
    git: {
      async listMatchingRefs(args) {
        calls.push(['listMatchingRefs', args]);
        return {data: refs('v2026.45.0')};
      },
      async getRef() {
        if (!state.ref) throw missing();
        return {data: state.ref};
      },
      async getTag() {return {data: state.tag};},
      async createTag(args) {
        calls.push(['createTag', args]);
        state.tag = {tag: args.tag, sha: 'd'.repeat(40), object: {type: args.type, sha: args.object}};
        return {data: state.tag};
      },
      async createRef(args) {
        calls.push(['createRef', args]);
        state.ref = {object: {type: 'tag', sha: args.sha}};
        return {data: state.ref};
      },
    },
    repos: {
      async getContent(args) {
        calls.push(['getContent', args]);
        return {data: {content: Buffer.from(`FROM ${baseImage}\n`).toString('base64')}};
      },
      async getReleaseByTag() {
        if (!state.release) throw missing();
        return {data: state.release};
      },
      async createRelease(args) {
        calls.push(['createRelease', args]);
        state.release = args;
        return {data: args};
      },
    },
  }};
  return {github, context, core, calls, outputs, state, version, sourceSha, digest, now};
}

test('versions start at zero and select the highest numeric patch for the current week', () => {
  assert.equal(nextVersion([], now), 'v2026.45.0');
  assert.equal(nextVersion(refs('v2026.45.0'), now), 'v2026.45.1');
  assert.equal(nextVersion(refs('v2026.45.9', 'v2026.45.2', 'v2026.45.10'), now), 'v2026.45.11');
  assert.equal(nextVersion(refs('v2026.44.99', 'v2025.45.8', 'v2026.45.1-rc1', 'v2026.45.2.0'), now), 'v2026.45.0');
  assert.equal(nextVersion(refs('v2026.45.3'), new Date('2026-11-08T12:00:00Z')), 'v2026.46.0');
  assert.equal(nextVersion(refs('v2026.53.3'), new Date('2027-01-01T12:00:00Z')), 'v2027.1.0');
});

test('manual preparation selects a version and freezes the source without creating tags', async () => {
  const f = fixture();
  await prepare(f);
  assert.deepEqual(f.outputs, {version, source_sha: sourceSha, base_image: '', should_release: 'true'});
  assert.deepEqual(f.calls.map(([name]) => name), ['listMatchingRefs']);
  assert.equal(f.calls[0][1].ref, 'tags/v2026.45.');
});

test('dev releases only when a push changes the base version or digest', async () => {
  for (const pin of [baseImage.replace('45.0', '45.1'), baseImage.replace('b'.repeat(64), 'e'.repeat(64))]) {
    const f = fixture();
    f.context.eventName = 'push';
    await prepare({...f, dev: true, dockerfile: `FROM ${pin}\nRUN echo change\n`});
    assert.equal(f.outputs.should_release, 'true');
    assert.equal(f.outputs.base_image, pin);
    assert.equal(f.calls[0][1].ref, f.context.payload.before);
  }
});

test('unrelated Dockerfile changes skip automatic dev releases', async () => {
  const f = fixture();
  f.context.eventName = 'push';
  await prepare({...f, dev: true, dockerfile: `FROM ${baseImage}\nRUN echo unrelated\n`});
  assert.deepEqual(f.outputs, {should_release: 'false'});
  assert.deepEqual(f.calls.map(([name]) => name), ['getContent']);
});

test('manual dev releases do not require a base pin change', async () => {
  const f = fixture();
  await prepare({...f, dev: true, dockerfile: `FROM ${baseImage}\n`});
  assert.equal(f.outputs.should_release, 'true');
  assert.equal(f.outputs.base_image, baseImage);
  assert.deepEqual(f.calls.map(([name]) => name), ['listMatchingRefs']);
});

test('dev base image must include a version and digest', () => {
  assert.equal(basePin(`FROM ${baseImage}\nARG TARGETARCH\n`), baseImage);
  assert.throws(() => basePin('FROM weblate/base:latest\n'), /must pin/);
});

test('finalization creates the annotation, then its ref, then the release', async () => {
  const f = fixture();
  await finalize({...f, baseImage});
  assert.deepEqual(f.calls.map(([name]) => name), ['createTag', 'createRef', 'createRelease']);
  assert.equal(f.calls[0][1].object, sourceSha);
  assert.equal(f.calls[1][1].sha, f.state.tag.sha);
  assert.notEqual(f.calls[1][1].sha, sourceSha);
  assert.equal(f.calls[1][1].ref, `refs/tags/${version}`);
  assert.equal(f.calls[2][1].generate_release_notes, true);
  assert.ok(f.state.summary.some(row => row.includes(`weblate/dev@${digest}`)));
  assert.ok(f.state.summary.some(row => row.includes(`ghcr.io/weblateorg/dev@${digest}`)));
  assert.ok(f.state.summary.some(row => row.includes(baseImage)));
  await finalize(f);
  assert.equal(f.calls.length, 3, 'retry must not recreate a tag or release');
});

test('missing publication output prevents any tag or release creation', async () => {
  const f = fixture();
  await assert.rejects(finalize({...f, digest: ''}), /valid digest/);
  assert.deepEqual(f.calls, []);
});

test('a release failure can be retried after the annotated tag was created', async () => {
  const f = fixture();
  const createRelease = f.github.rest.repos.createRelease;
  f.github.rest.repos.createRelease = async () => {throw new Error('Release failed');};
  await assert.rejects(finalize(f), /Release failed/);
  assert.ok(f.state.ref);
  f.github.rest.repos.createRelease = createRelease;
  await finalize(f);
  assert.deepEqual(f.calls.map(([name]) => name), ['createTag', 'createRef', 'createRelease']);
});

test('conflicting or lightweight existing tags cannot be reused', async () => {
  for (const type of ['commit', 'tag']) {
    const f = fixture();
    f.state.ref = {object: {type, sha: 'd'.repeat(40)}};
    f.state.tag = {tag: version, object: {type: 'commit', sha: 'e'.repeat(40)}};
    await assert.rejects(finalize(f), /not an annotated tag|different object/);
    assert.deepEqual(f.calls, []);
  }
});

test('authorization failures are not treated as missing tags', async () => {
  const f = fixture();
  f.github.rest.git.getRef = async () => {throw Object.assign(new Error('Forbidden'), {status: 403});};
  await assert.rejects(finalize(f), /Forbidden/);
  assert.deepEqual(f.calls, []);
});

test('ref creation failure prevents release publication', async () => {
  const f = fixture();
  f.github.rest.git.createRef = async () => {throw new Error('Ref failed');};
  await assert.rejects(finalize(f), /Ref failed/);
  assert.equal(f.state.release, null);
});
