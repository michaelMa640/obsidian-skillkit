# Category Rules

Use this file when the target vault does not already make the classification obvious.

## Folder selection order

1. Prefer an exact existing folder match in the vault.
2. Prefer a semantic match over a file-format match.
3. Prefer a stable long-term home over a temporary working folder.
4. Fall back to `Inbox/`, `Capture/`, or `Sources/` if confidence is low.

## Default heuristics

- `Research/` or `Papers/`: research papers, whitepapers, technical reports, benchmarks, deep investigations
- `Articles/` or `Reading/`: blog posts, essays, newsletters, opinion pieces, explainers
- `Videos/` or `Media/`: video transcripts, podcasts, interviews, talks
- `Tools/` or `Software/`: product pages, release notes, library introductions, tool evaluations
- `People/`: interviews, biographies, creator profiles, founder notes
- `Projects/`: source material directly tied to an active project or client deliverable
- `Methods/` or `Playbooks/`: step-by-step workflows, frameworks, operating procedures
- `Clippings/` or `Sources/`: source-preserving archives when the vault intentionally separates raw references from evergreen notes

## Title rules

- Prefer the source title if it is specific and readable.
- Rewrite clickbait headlines into neutral, searchable titles.
- Add a clarifier when needed, such as `(Paper)`, `(Interview)`, or `(Tool)`.

## Tags

Prefer a small tag set:
- one topic tag
- one format or source-type tag
- one project or domain tag if relevant

Examples:
- `ai`, `article`, `research-workflow`
- `product-strategy`, `video`, `startup`
- `obsidian`, `tool`, `knowledge-management`

## Minimum useful note

Even when extraction quality is uneven, preserve:
- title
- source reference
- capture date
- 3 or more key takeaways
- at least one sentence explaining why the note matters
