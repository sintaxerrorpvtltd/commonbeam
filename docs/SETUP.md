# Setup and removal

Use the model-free quickstart in README.md. A source build downloads Swift library
dependencies; it never downloads an AI model. Node client runtime dependencies: none.

## Native control app

Run `sh scripts/package-app.sh`, then open `dist/Commonbeam.app`.
This creates a locally ad-hoc signed developer bundle, not a notarized distribution.
Select Synthetic test mode to exercise grants/streaming without a model.
Normal mode exposes unavailable local-text readiness.

Starting the service creates an app-specific Keychain item under service
`com.commonbeam.local-alpha.grant-key`, account `verifier`. Grant verifiers
are stored at `~/Library/Application Support/Commonbeam-Local-Alpha/grants.json`
(directory 0700, file 0600). Existing insecure modes are rejected. Tokens are
displayed once and not persisted by Commonbeam. Keep caller tokens in Keychain;
for the CLI examples use private, user-owned 0600 files.

There are no login items. Quit cancels the owned service. The listener defaults to
127.0.0.1:52441; a collision is an error, not permission to stop another process.
An old foundation grant does not authorize fixture-text revision 2. Future real
models must advance profile revisions and require explicitly approved grants.

## CLI fixture server

Run `swift run CommonbeamFixtureServer PORT NEW_DIRECTORY`.
The directory must not exist. Two secrets are written privately and never printed.
Use Ctrl-C for graceful shutdown/removal. If the process is killed abruptly, remove
only that exact test directory after stopping the server. No Keychain or model store
is used by this fixture executable.

## Removal

Quit Commonbeam, then remove its app bundle. If you want to erase stored grants,
remove only Commonbeam-Local-Alpha in your Application Support folder and the exact
Keychain item above. Removing the verifier key invalidates existing grants.
Build output lives in .build and dist and can be removed independently.

Leave unrelated Keychain items, provider files and Apple assets alone. No provider
process is started, stopped, configured or deleted by this preview.
