# Contributing

`master` is protected. Do not push directly to it after the initial bootstrap.

1. Branch from current `master` using `codex/<short-topic>`.
2. Make one focused change and run the repository checks locally.
3. Push the branch and open a pull request with `gh pr create`.
4. Wait for the required CI checks with `gh pr checks --watch`.
5. Merge passing pull requests using `gh pr merge --squash --delete-branch`.

The initial repository owner may merge their own passing pull requests; no
review approval is required. Resolve all review conversations before merging.
