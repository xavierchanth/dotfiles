# Clarity themes

The Clarity family is inspired by Atom One and Tokyo Night.

The theme definitions in `definitions/` are the source of truth. Generated
Ghostty themes in `../stow/ghostty-themes/` and viewer data are committed so
changes can be reviewed and used without running a build-time generator.

## Themes

- **Clarity Paper**: crisp, high-contrast light palette.
- **Clarity Solarized**: warm paper palette with blue-green neutrals.
- **Clarity Dusk**: deep-blue dark palette.
- **Clarity Midnight**: near-black dark palette.

## Commands

```sh
./themes/generate.py generate
./themes/generate.py check
./themes/generate.py refresh-profiles
./themes/generate.py preview
```

`refresh-profiles` captures Neovim's
light and dark `:highlight` output. It does not read authentication or session
files. The generator never commits changes.
