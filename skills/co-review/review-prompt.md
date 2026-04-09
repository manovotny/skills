## Pre-review

1. Read the PR title and description for context using `gh pr view {PR_NUMBER}`.
2. If the PR description contains links to other PRs and repos as reference, read those too for more context.
3. Find and read any CLAUDE.md or AGENTS.md files to gain project-specific context.
4. Find and read any CONTRIBUTING* or STYLEGUIDE* files (e.g., CONTRIBUTING.md, CONTRIBUTING-COMPONENTS-HOOKS.md, STYLEGUIDE.md, SSO.STYLEGUIDE.md) to ensure the PR follows project rules and best practices.
5. Check for symlinked repositories in the workspace. Use them to verify code examples, API references, and technical details when available.

## Review

The changes already exist locally. Review the diff using `gh pr diff {PR_NUMBER}`, focusing on:

### What to review

1. **Logic and correctness** — Check for bugs, edge cases, technical accuracy, inaccurate comments, syntax errors, and potential issues. Is this the best possible, most long term maintainable way to solve this problem, or are there alternative or simpler solutions that we should consider?
2. **Readability** — Is the code clear and maintainable? Does it follow best practices in this repository?
3. **Performance** — Are there obvious performance concerns or optimizations that could be made? Fetches that could be parallelized, loops that could be optimized, etc.
4. **Test coverage** — Does the repository have testing patterns? If so, are there adequate tests for these changes? Skip for documentation-only changes.
5. **Content** — If there are content changes, review code in code blocks as if you're reviewing actual code. Assess content flow, content hierarchy, typos, ambiguity that needs to be clarified, and verbosity that needs to be simplified.

### How to review

- Flag uncertainty explicitly rather than asking clarifying questions.
- Don't be overly pedantic. Nitpicks are fine, but only if they are relevant issues within reason.

## Output

- Provide a succinct summary of general code quality.
- Present identified issues in a list with: index (1, 2, etc.), file, line number(s), severity (bug, suggestion, nit), code, issue, and potential solution(s) in the following format:

  1. {issue title}
  File: {relative path to file}
  Line(s): {line numbers}
  Severity: {bug, suggestion, nit}
  Code: {relevant code snippet}
  Issue: {issue summary}
  Solutions: {potential solutions}

  ---

  2. {issue title}
  // and so on...

- If no issues are found, briefly state that the code meets best practices.
