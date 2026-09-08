# DocsMap

Documentation components this project declares. One H2 per component; the format and the
doctrine are `conventions/docs-components.md`. Delete the examples below and declare what this
project actually has — an empty file is a valid registry and means the mechanism stays quiet.

A package with its own documentation declares it in its own `DocsMap.md`, at the package root,
with paths relative to that root. Every project holding that package reads the same record.

## Example-State

genre: state
strictness: advisory
places:
  - Documents/Example/
covers:
  - Sources/Example/**

## Example-Progress

genre: progress
strictness: advisory
places:
  - Progress/Example-Progress.md
fed_by:
  - Tasks/*/*-example-*
