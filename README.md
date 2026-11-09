<!--
Copyright © Michal Čihař <michal@weblate.org>

SPDX-License-Identifier: MIT
-->
# docker-base

Base image for Weblate Docker container

<p>
  <a href="https://weblate.org/">
    <img alt="Weblate"
         src="https://s.weblate.org/cdn/Logo-Darktext-borders.png"
         height="55">
  </a>
</p>

Part of [Weblate](https://weblate.org/) — a privacy-respecting localization platform built on open-source foundations.

## Publishing releases

The weekly schedule and **Run workflow** in the **Release** workflow start a release.

The workflow selects the next `vYEAR.WEEK.PATCH` version, builds the selected
commit for amd64 and arm64, and publishes images to Docker Hub and GHCR. Only
then does it create the annotated Git tag and GitHub release. The workflow
summary records the source commit and published image digest.

Failed checks or image publication do not create a Git tag or GitHub release.
A registry push can succeed before another fails; rerun failed jobs to complete
the same version. Finalization can also be retried after tag creation without
recreating the tag. Release runs are serialized to prevent version collisions.

Branch, pull-request, daily, and manual image builds remain separate from
versioned releases. Run `node --test tests/release.test.cjs` to check the release
logic locally.
