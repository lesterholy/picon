# Repository Guidelines

## Project Structure & Module Organization

This repository is currently a starter workspace. The only existing project-local directory is `.omx/`, which stores automation state and logs; do not treat it as application source. As code is added, keep the layout predictable:

- `src/` for application or library source.
- `tests/` for automated tests that mirror `src/` paths.
- `assets/` for static images, fixtures, or other non-code resources.
- `docs/` for design notes, architecture decisions, and contributor-facing references.

Prefer small modules with clear ownership. Avoid mixing generated files, runtime logs, and hand-edited source.

## Build, Test, and Development Commands

No package manifest, build script, or test runner is committed yet. Add the appropriate tool entry when the first implementation stack is introduced, then keep this section current. Common patterns:

- `npm install` / `npm test` / `npm run build` for Node projects.
- `python -m pytest` for Python tests.
- `make test` or `make build` if a `Makefile` becomes the project command surface.

Before opening a PR, run the project’s documented test and build commands from the repository root.

## Coding Style & Naming Conventions

Use the formatter and linter native to the selected stack, and commit their configuration with the code. Until a stack-specific rule exists, use 2-space indentation for JavaScript/TypeScript/JSON/YAML and 4-space indentation for Python. Name files descriptively: `kebab-case` for web assets, `snake_case.py` for Python modules, and `PascalCase.tsx` for React components.

Keep changes focused and avoid adding dependencies unless they are needed for the task.

## Testing Guidelines

Place tests under `tests/` or alongside source using the stack’s standard convention. Name tests after the behavior under test, for example `tests/test_parser.py` or `src/parser.test.ts`. Add regression tests for bug fixes and cover new public behavior before refactoring.

## Commit & Pull Request Guidelines

Git history is not available in this workspace, so no repository-specific commit pattern can be inferred. Use concise, imperative commit subjects such as `Add parser validation tests`. Pull requests should include a short summary, verification commands run, linked issues when relevant, and screenshots for UI changes.

## Agent-Specific Notes

Keep `.omx/` runtime files out of normal feature edits unless explicitly working on automation state. Update this guide whenever project structure, commands, or conventions become concrete.
