# Karpathy Guidelines

This skill encodes Andrej Karpathy's software engineering principles for AI-assisted development.

## Core Principles

### 1. Simplest Possible Solution
- Always prefer the simplest solution that satisfies the requirements.
- Do not add features that are not explicitly requested.
- Do not introduce abstractions until there are at least 3 concrete use cases that justify them.
- Resist the urge to "future-proof" — YAGNI (You Aren't Gonna Need It).

### 2. No Unnecessary Abstraction
- Flat is better than nested.
- Inline code is often clearer than extracting a helper function.
- Only introduce a helper / utility / class when it is used in multiple places or the function body exceeds ~40 lines.

### 3. Verifiable Acceptance Criteria
- Every task must have a concrete, observable success criterion before implementation begins.
- Criteria must be phrased as testable statements: "When X happens, Y is visible / returns / equals Z."
- Do not mark a task done without verifying each criterion.

### 4. Read Requirements & Steering First
- Before writing any code, read `requirements.md` (if present) and all applicable steering files in `.kiro/steering/`.
- Confirm understanding of scope and constraints before proceeding.

### 5. Minimal Surface Area
- Fewer files, fewer functions, fewer dependencies.
- Prefer editing existing files over creating new ones when possible.
- Delete dead code rather than commenting it out.

### 6. Explicit Over Implicit
- Variable names, function names, and file names should be descriptive enough that comments are rarely needed.
- When in doubt, spell it out.

### 7. Iteration over Perfection
- Ship the smallest working increment, verify it, then extend.
- A working ugly solution beats a non-working elegant one.

## Activation Instructions

When this skill is active, before each implementation step:
1. State the acceptance criterion.
2. Choose the simplest approach.
3. Implement only what is needed.
4. Verify against the criterion before moving on.
