---
name: release
description: >
  Create a tagged release (major, minor, or patch). Updates CHANGELOG.md with
  commits since the last tag, creates an annotated git tag with changelog notes.
  Trigger when: user says "release", "tag a release", "bump version", "new release",
  or "/release [major|minor|patch]".
---

# Release

Create a semantically versioned release with changelog and annotated tag.

## Invocation

```
/release <major|minor|patch>
```

Argument is required. If omitted, ask the user which bump level they want.

## Procedure

1. **Determine current version** — `git tag --sort=-v:refname | head -1`. Tags use semver without `v` prefix (e.g. `0.11.0`).

2. **Compute next version** — bump the requested component, reset lower components to 0.

3. **Gather commits** — `git log --format="- %s" <current>..HEAD`. If empty, abort: "No commits since last release."

4. **Determine today's date** — use the current date context (YYYY-MM-DD format).

5. **Update CHANGELOG.md** — prepend a new section after the `# Changelog` heading:

   ```
   ## X.Y.Z — YYYY-MM-DD

   <commits grouped by type>
   ```

   Group commits under Keep a Changelog headings (`### Added`, `### Changed`, `### Fixed`, `### Removed`) based on conventional-commit prefixes:
   - `feat:` → Added
   - `fix:` → Fixed
   - `refactor:`, `chore:`, `docs:`, `build:`, `ci:` → Changed
   - Lines not matching a prefix go under Changed.
   - Omit empty groups. Strip the prefix from each line.

6. **Commit the changelog** — `git add CHANGELOG.md && git commit -m "docs: add X.Y.Z changelog"`

7. **Create annotated tag** — use the changelog section (without the `##` heading) as the tag message:

   ```
   git tag -a X.Y.Z -m "<tag message>"
   ```

8. **Report** — show the tag name and a short summary. Do NOT push unless the user asks.
