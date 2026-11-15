# Demo library

A sample set of snippets with color groups, for trying Snippet Studio without touching your own Espanso files:

```sh
SNIPPET_STUDIO_DEMO="$PWD/demo" ~/Applications/Snippet\ Studio.app/Contents/MacOS/SnippetStudio
```

- `match/demo.yml` holds the snippets, in ordinary Espanso format.
- `appearance.json` holds the color groups and icons.
- Backups made in demo mode go to `demo/Backups/`, which git ignores.

Espanso itself doesn't load these snippets; they only exist for the app.
