# Documentation Components

A documentation component is a file or section within the project's documentation that tracks its own synchronization state with the code.

## Registry

A project declares its documentation components in a `DocsMap.md` file, located at the path named by the `map` key in the project config's `## Docs` block.

The registry structure and the mechanism for routing changes to documentation are defined by the `docs-route` skill.

## Inheritance

When a package is listed in `## Paths` under `External packages`, its `DocsMap.md` (if it exists) contributes its components to the consuming project's documentation registry.
