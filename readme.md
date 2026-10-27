# Afright game script loader

`loader.lua` selects and runs a game script from the public [Casual0developer/Afright](https://github.com/Casual0developer/Afright) repository. Scripts are selected by the current Roblox `game.PlaceId`.

## Repository layout

Keep the loader and each game script at the repository root:

```text
loader.lua
113273588963037.lua
<another PlaceId>.lua
```

Each numbered `.lua` file contains the complete script for that place. The existing `113273588963037.lua` is one such script.

## How selection works

1. The loader reads `game.PlaceId` and forms the exact filename `<PlaceId>.lua`.
2. It requests the file list for the repository's `main` branch from the GitHub API and checks the root-level files for that exact name.
3. If a match exists, it downloads that file from `raw.githubusercontent.com`, compiles it with `loadstring`, and runs it once.
4. If the GitHub API is unavailable or rate limited, it tries the exact raw file URL directly. If no file exists or the download fails, it runs nothing and prints a diagnostic.

`game.PlaceId` is intentional: the existing game script checks `PlaceId`, not `game.GameId`. Files such as `113273588963037-copy.lua`, `113273588963037.lua.txt`, and `loader.lua` never match.

## Instructions for adding scripts and for AI assistants

1. Add a file named exactly `<numeric PlaceId>.lua` to the repository root on the `main` branch.
2. Put the complete Luau script for that place in the numbered file. Keep game-specific behavior out of `loader.lua`.
3. Do not hardcode a list of PlaceIds or copy scripts into the loader. It discovers new numbered files automatically.
4. Keep the `Casual0developer/Afright` repository and `main` branch settings in `loader.lua` synchronized if the repository moves.
5. Verify the exact numbered file is accessible on GitHub before testing the loader in that Roblox place.

The loader uses `game:HttpGet` and `loadstring`, so the executor must support both. It does not use the executor's local `listfiles` or `readfile` APIs. Editing a local copy alone does not update the hosted loader; publish changes to GitHub before running the hosted version.
