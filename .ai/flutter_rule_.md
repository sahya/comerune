## Purpose
This file defines project rules for AI agents working on this Flutter application.
Agents must follow these rules to keep implementation consistent, reviewable, and maintainable.

---

## Core Principles
- Prefer small, explicit, and testable changes.
- Do not introduce architectural changes unless explicitly requested.
- Respect existing patterns before inventing new ones.
- Optimize for readability and maintainability over cleverness.
- Keep issue scope narrow. Do not bundle unrelated work.

---

## Product Safety Rules
- Do not invent major product requirements.
- If the specification is ambiguous, state assumptions clearly before implementation.
- If behavior is not defined, prefer minimal and conservative implementation.
- Do not silently add extra UI behavior, navigation, background processing, caching, or analytics.

---

## Scope Control
For every task:
1. restate the goal
2. restate the scope
3. restate the non-scope
4. list likely files to change
5. list assumptions and risks
6. list implementation steps

Before finishing, always report:
1. files changed
2. what was implemented
3. what was intentionally not implemented
4. test/analyze results
5. remaining risks or follow-up items

---

## Architecture Rules
- Preserve the current project structure.
- Do not migrate architecture patterns without approval.
- Do not change the state management solution unless explicitly required.
- Do not change routing, dependency injection, network layer, persistence layer, or app bootstrap flow unless the issue requires it.
- Keep presentation, state handling, domain logic, and data access separate.
- Avoid putting API calls directly inside widgets unless the project already uses that pattern consistently.

---

## Directory Responsibility Rules
Unless the project already uses a different pattern, prefer these boundaries:

- `presentation/`
  - screens, widgets, UI-only helpers
  - no direct networking or persistence logic

- `application/` or `state/`
  - state notifiers, controllers, view models, blocs, cubits, providers
  - coordinates UI actions and business flow

- `domain/`
  - entities, value objects, pure business logic, validation rules
  - framework-independent where practical

- `data/`
  - repositories, data sources, DTOs, API clients, persistence adapters
  - maps external data to internal models

- `test/`
  - unit tests, widget tests, integration tests

If the repository already uses another structure, follow the existing structure instead of forcing this one.

---

## UI Rules
- Keep widgets focused and reasonably small.
- Extract repeated UI into reusable widgets only when reuse is real, not speculative.
- Prefer clear widget composition over deep abstraction.
- Do not add visual polish beyond the issue scope.
- Do not change theme, spacing system, typography, colors, or design language unless explicitly requested.
- For loading, empty, error, and disabled states, implement only what the issue or spec requires.

---

## State Management Rules
- Follow the existing state management approach already used in the project.
- Do not introduce a second state management style unless explicitly requested.
- Keep transient UI state separate from app/business state where practical.
- Avoid mixing validation logic, networking, and widget rendering in one place.
- Prefer predictable, explicit state transitions.

When adding state:
- define idle/loading/success/error states if relevant
- keep state names concrete
- avoid “magic booleans” when a named state model is clearer

---

## Data and Networking Rules
- Keep API access, persistence, and repository logic out of widgets.
- Do not introduce new API clients or repositories if an existing one should be extended.
- Keep DTOs and domain models distinct when the project already distinguishes them.
- Be explicit about mapping and null handling.
- Prefer safe parsing and defensive handling of malformed or partial data.
- Do not silently swallow exceptions.

---

## Error Handling Rules
- Handle expected failure cases explicitly.
- Do not show raw exception text directly to end users unless the project already does so intentionally.
- Distinguish:
  - validation errors
  - network/API errors
  - empty states
  - unexpected internal failures
- Use project-consistent patterns for retries, snackbars, dialogs, banners, or inline errors.
- If error UX is not specified, implement the smallest consistent behavior.

---

## Validation Rules
- Keep validation logic centralized when practical.
- Do not duplicate validation rules across widget, state, and data layers unless necessary.
- Prefer deterministic and testable validation functions.
- Make validation messages consistent with existing UX wording.
- If validation requirements are incomplete, implement the minimum conservative rule set and document assumptions.

---

## Null Safety and Types
- Use sound null safety correctly.
- Avoid force unwrap patterns unless safety is guaranteed and obvious.
- Prefer explicit types at boundaries.
- Avoid dynamic typing unless required by an external API.
- Keep conversions and casts localized and justified.

---

## Dependency Rules
- Do not add a package unless clearly necessary for the issue.
- If a new dependency is needed, explain:
  - why it is needed
  - why current dependencies are insufficient
  - the expected impact area
- Prefer mature, minimal dependencies.
- Avoid dependency sprawl for small conveniences.

---

## Testing Rules
Agents must consider tests for every non-trivial change.

Prefer:
- unit tests for pure logic and validation
- widget tests for UI behavior and state-driven rendering
- integration tests only when flows genuinely require them

At minimum:
- new business logic should have unit tests where practical
- bug fixes should include regression coverage where practical
- UI behavior changes should have widget tests where practical

Do not claim coverage that was not actually added.

---

## Test Design Rules
- Test observable behavior, not internal implementation details, unless no better boundary exists.
- Keep tests readable and deterministic.
- Avoid brittle timing-dependent tests when possible.
- Prefer small focused tests over giant end-to-end tests.
- Reuse helpers carefully; do not hide test intent behind excessive abstraction.

---

## Performance and Rebuild Rules
- Avoid unnecessary rebuilds in frequently rendered widgets.
- Do not prematurely optimize.
- When touching lists, images, scrolling, or repeated widgets, avoid obviously wasteful patterns.
- Prefer const constructors where appropriate and consistent with project style.

---

## Accessibility and UX Consistency
- Preserve existing semantics and interaction patterns where practical.
- Do not remove labels, hints, or tappable affordances without reason.
- Keep text and control behavior consistent with nearby screens.
- Avoid surprising navigation or destructive actions.

---

## Logging and Debugging Rules
- Do not leave debug prints in production code.
- Use existing logging facilities if the project has them.
- Keep logs minimal and purposeful.
- Do not log secrets, tokens, or personal data.

---

## Security Rules
- Never hardcode secrets, tokens, API keys, or credentials.
- Do not weaken auth, permission, or validation checks unless explicitly required and approved.
- Treat external input as untrusted.
- Be cautious with WebView, file access, local storage, and background execution.
- Follow least-privilege thinking for permissions and data exposure.

---

## Refactoring Rules
- Do not perform broad refactors during feature implementation unless explicitly requested.
- If a small local refactor is necessary to implement the issue safely, keep it minimal and explain it.
- Separate cleanup from product behavior whenever possible.

---

## Review Checklist
Before marking work complete, verify:
- Is the implementation within scope?
- Are acceptance criteria satisfied?
- Were unrelated files avoided?
- Is architecture consistency preserved?
- Are validation and error cases handled?
- Were tests added where practical?
- Were `dart format`, `flutter analyze`, and `flutter test` run if available?
- Were assumptions documented clearly?

---

## Required Commands
Run these when possible:
- `dart format .`
- `flutter analyze`
- `flutter test`

If any command cannot be run, state exactly why.

---

## Forbidden Behavior
Do not:
- invent large features not in the issue
- change architecture without approval
- add packages casually
- mix unrelated refactors with feature work
- skip error handling where it obviously matters
- claim tests passed if they were not run
- hide assumptions
- mark work complete while acceptance criteria are unmet

---

## Preferred Response Style for the Human Owner
The project owner may not want deep Flutter jargon.
When reporting:
- explain changes concretely
- mention affected files
- mention user-visible behavior
- mention risk in plain language
- avoid abstract design language when simple wording is enough

Good example:
- "This change adds form validation in the login screen and prevents submit when input is invalid."

Bad example:
- "This introduces a more canonical separation of concerns in the presentation layer."

---

## Default Implementation Posture
When uncertain:
- choose the smaller change
- choose the more explicit implementation
- avoid hidden side effects
- document assumptions
- ask for approval through structured output rather than improvising