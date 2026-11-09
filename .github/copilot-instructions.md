# Release packaging

When asked to package a release for manual CurseForge upload:

- Run `powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\package-release.ps1` from the repository root.
- The script uses the version in `SabotonEssentials.toc` and packages the current working files, including uncommitted changes, into the Git-ignored `releases` folder.
- Do not overwrite or delete an existing release ZIP without the user's approval. If the requested version already exists, ask how to proceed.
- Check the generated ZIP has the `SabotonEssentials` root folder, matching TOC and required runtime files. Tell the user its path and that the upload is manual.
- Do not create a tag, commit, push, or upload unless explicitly requested.