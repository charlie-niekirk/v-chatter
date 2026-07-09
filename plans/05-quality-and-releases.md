# 5 — Quality gates and releases

## Goal

Make every merge verifiable and publish reproducible unsigned macOS releases.

## Work

- Keep CI jobs `validate`, `test`, and `build` required on every pull request
  and `master` push. Pin action and Native SDK CLI versions deliberately; test
  any version update in its own PR.
- Add a required `ui-smoke` job once the automation journal/mock services
  exist, then update branch protection with `gh api` to require `CI / ui-smoke`.
  Avoid workflow path filters that could leave required checks pending.
- Add a tag-triggered `v*` release workflow that builds and packages unsigned
  Apple Silicon and Intel artifacts, verifies their contents, uploads workflow
  artifacts, and creates the GitHub release with `gh release create`.
- Add a release checklist covering version update, changelog, macOS Gatekeeper
  warning, public Client ID configuration, and a manual login/live-chat smoke
  test. Do not add Apple signing or notarization in this phase.
- Maintain Dependabot updates for GitHub Actions. Review each bot PR through
  the same required checks and squash-only workflow.

## Acceptance

- A deliberately failing unit/build/UI test blocks a PR merge.
- A version tag produces both documented unsigned macOS artifacts and a GitHub
  release only after all packaging checks pass.
- `master` remains protected: PR required, no approval count, conversations
  resolved, strict checks, linear history, no admin bypass, and no force push
  or deletion.

## Dependencies

Foundation through native interface. The release workflow may be added before
emote work, but UI smoke cannot be required until its automation exists.
