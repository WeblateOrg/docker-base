// Copyright © Michal Čihař <michal@weblate.org>
//
// SPDX-License-Identifier: MIT

const {readFileSync} = require('node:fs');

function nextVersion(refs, now = new Date()) {
  const year = now.getUTCFullYear();
  const onejan = new Date(Date.UTC(year, 0, 1));
  // Preserve the existing release calendar; this is not an ISO week number.
  const week = Math.ceil((((now - onejan) / 86400000) + onejan.getUTCDay() + 1) / 7);
  const prefix = `refs/tags/v${year}.${week}.`;
  let patch = 0;
  for (const {ref} of refs) {
    if (ref.startsWith(prefix) && /^\d+$/.test(ref.slice(prefix.length))) {
      patch = Math.max(patch, Number(ref.slice(prefix.length)) + 1);
    }
  }
  return `${prefix.slice('refs/tags/'.length)}${patch}`;
}

function basePin(dockerfile) {
  const match = dockerfile.match(/^FROM (weblate\/base:[^\s@]+@sha256:[a-f0-9]{64})\s*$/m);
  if (!match) {
    throw new Error('Dockerfile must pin weblate/base to a version and SHA-256 digest');
  }
  return match[1];
}

async function prepare({github, context, core, dev = false, now = new Date(), dockerfile}) {
  let baseImage = '';
  if (dev) {
    baseImage = basePin(dockerfile ?? readFileSync('Dockerfile', 'utf8'));
    if (context.eventName === 'push') {
      const {data: previous} = await github.rest.repos.getContent({
        ...context.repo,
        path: 'Dockerfile',
        ref: context.payload.before,
      });
      const previousPin = basePin(Buffer.from(previous.content, 'base64').toString('utf8'));
      if (baseImage === previousPin) {
        core.setOutput('should_release', 'false');
        core.info('Base image pin is unchanged; no release needed');
        return;
      }
    }
  }
  // The prefix is calculated from the same date used for the final version.
  const prefix = nextVersion([], now).replace(/0$/, '');
  const {data: refs} = await github.rest.git.listMatchingRefs({
    ...context.repo,
    ref: `tags/${prefix}`,
  });
  core.setOutput('version', nextVersion(refs, now));
  core.setOutput('source_sha', context.sha);
  core.setOutput('base_image', baseImage);
  core.setOutput('should_release', 'true');
}

async function optionalRequest(request) {
  try {
    return (await request()).data;
  } catch (error) {
    if (error.status !== 404) {
      throw error;
    }
    return null;
  }
}

async function finalize({github, context, core, version, sourceSha, digest, baseImage = ''}) {
  if (!/^v\d{4}\.\d{1,2}\.\d+$/.test(version) || !/^[a-f0-9]{40}$/.test(sourceSha)) {
    throw new Error('Invalid release version or source commit');
  }
  if (!/^sha256:[a-f0-9]{64}$/.test(digest)) {
    throw new Error('Image publication did not return a valid digest');
  }
  const existing = await optionalRequest(() => github.rest.git.getRef({
    ...context.repo,
    ref: `tags/${version}`,
  }));
  if (existing) {
    if (existing.object.type !== 'tag') {
      throw new Error(`Existing ${version} is not an annotated tag`);
    }
    const {data: tag} = await github.rest.git.getTag({
      ...context.repo,
      tag_sha: existing.object.sha,
    });
    if (tag.tag !== version || tag.object.type !== 'commit' || tag.object.sha !== sourceSha) {
      throw new Error(`Existing ${version} targets a different object`);
    }
  } else {
    const {data: tag} = await github.rest.git.createTag({
      ...context.repo,
      tag: version,
      message: `chore: automatically tagged release ${version}`,
      object: sourceSha,
      type: 'commit',
    });
    await github.rest.git.createRef({
      ...context.repo,
      ref: `refs/tags/${version}`,
      sha: tag.sha,
    });
  }
  const release = await optionalRequest(() => github.rest.repos.getReleaseByTag({
    ...context.repo,
    tag: version,
  }));
  if (!release) {
    await github.rest.repos.createRelease({
      ...context.repo,
      tag_name: version,
      generate_release_notes: true,
    });
  }
  const image = context.repo.repo.replace('docker-', '');
  const rows = [
    ['Version', version],
    ['Source commit', sourceSha],
    ['Docker Hub', `weblate/${image}@${digest}`],
    ['GHCR', `ghcr.io/weblateorg/${image}@${digest}`],
  ];
  if (baseImage) {
    rows.push(['Base image', baseImage]);
  }
  await core.summary.addHeading('Published release').addTable(rows).write();
}

module.exports = {nextVersion, basePin, prepare, finalize};
