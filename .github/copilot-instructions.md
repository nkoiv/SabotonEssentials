# Testing and releases

- Use standard Lua 5.1 for release validation: run every `tests/test_*.lua` file from the repository root, as in `.github/workflows/release.yml`. Fengari is useful for targeted checks but is not equivalent: Lua 5.1 rejected a UTF-8 BOM that Fengari accepted. If Lua 5.1 is unavailable, state that explicitly; do not claim native validation passed.
- For release packaging and publishing, follow the README's Tests and Releases sections and inspect the current workflow before acting.
- The local packaging command is `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\package-release.ps1` from the repository root. It uses the TOC version and packages current working files, including uncommitted changes, into the Git-ignored `releases` folder.
- Do not overwrite or delete an existing release ZIP without the user's approval. If the requested version already exists, ask how to proceed. Verify the archive's root folder, TOC version and entries, runtime files, and linked documentation.
- A pushed version tag triggers `.github/workflows/release.yml`: it can publish a GitHub release and, if configured, upload to CurseForge. Before pushing, check the tag and remote state, confirm the requested publishing destinations and inspect configuration without exposing credentials. Do not tag, commit, push, or upload unless the user requested those actions.
- Do not move, delete, or replace a published tag without explicit approval. If a pushed release tag needs correction, ask whether to use a new version instead.
- After publishing, check the workflow conclusion and the actual GitHub release, version, and ZIP asset. If uploading manually, verify the uploaded asset matches the intended archive; report failures and incomplete checks rather than assuming success.
- The workflow builds in the hidden `.release` directory. When changing artifact upload steps, preserve hidden-file inclusion; verify a real workflow run before claiming such changes work.

For a local-only ZIP, provide its path and make clear that it has not been uploaded.