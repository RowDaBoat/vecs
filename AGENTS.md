# Vecs
## Project
`vecs` is an ECS core for game engines.

- Author: Row/RowDaBoat (Me)
- Issues are tracked as VEPs (Vecs Enhancement Prompts) in the `issues` directory.
- The roadmap is tracked in the `roadmap.md` file.
- `VEP 0` outlines how to write VEPs.

Changes must be localized to the task we're focusing on, any extra change outside of our current focus will only generate friction.
Answers must be technical and honest.

## Tech stack
nim, ECS architecture, arrays of structures.

## Code style
- Semantic naming over comments, avoid comments unless absolutely necessary.
- Never-nester principle: max 1-2 nesting levels; extract methods instead.
- No `continue` in loops; extract the loop's body to it's own `proc` and use early returns.
- `camelCase` for procs/variables, `PascalCase` for types.
- Two blank lines between proc/type declarations.
- Use named variables to avoid too much inlining.
- Full words for variable names (no abbreviations).
- Functions should do one thing.
- Commit messages: brief, intention-focused.

## Markdown style
- Two blank lines before titles.
- Text on immediate next line after a title.
