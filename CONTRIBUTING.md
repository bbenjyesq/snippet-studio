# Contributing to Snippet Studio

Thanks for your interest! Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

Open an [issue](https://github.com/bbenjyesq/snippet-studio/issues/new/choose) and include:

- your macOS and Espanso versions (`espanso --version`)
- what you did, what you expected, and what happened
- if a particular snippet is involved, a **made-up** snippet that shows the same problem. Please never paste private snippet text.

## Building and testing

```sh
xcode-select --install   # once, if you don't have the Command Line Tools
swift test               # run the test suite
bash make-app.sh         # build and install ~/Applications/Snippet Studio.app
```

To try changes without touching your own snippets, run the app on the sample library:

```sh
SNIPPET_STUDIO_DEMO="$PWD/demo" ~/Applications/Snippet\ Studio.app/Contents/MacOS/SnippetStudio
```

## Pull requests

- Keep each pull request focused on one change, and match the surrounding code's style.
- Add or update a test for any change to `SnippetCore`, the file reading, editing, saving or backup logic. The safety guarantees in [How it works](docs/HOW-IT-WORKS.md) are covered by tests and must stay that way.
- Use invented sample data in tests and screenshots, never real snippets.
- `swift test` must pass; CI runs it on every pull request.

## Ground rules

- Snippet Studio never adds networking, telemetry, or anything that sends snippet text off the Mac.
- New dependencies need a strong reason and must be pinned to an exact version.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
