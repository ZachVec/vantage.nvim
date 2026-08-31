---
name: domain-modeling
description: Build and sharpen Vantage's domain model. Use when discussing codebase terminology, editing docs/glossary.md, or recording a decision as an Agent Note in .agents/notes/.
---

# Domain Modeling (Vantage)

Actively build and sharpen the project's domain model as you design. This is the *active* discipline — challenging terms, inventing edge-case scenarios, and writing the glossary and decisions down the moment they crystallise. (Merely *reading* `docs/glossary.md` for vocabulary is not this skill — that's a one-line habit any skill can do. This skill is for when you're changing the model, not just consuming it.)

## Where things live

Vantage is a single-context repo with two homes:

- **Glossary** — `docs/glossary.md`, one `## Term` heading per term (a definition, then an `_Avoid:` line naming rejected synonyms). The file is the format exemplar; create or edit a term only there.
- **Decisions** — Agent Notes under `.agents/notes/`, not ADRs. When and how to record one is the repo's rule in `.agents/notes/README.md` (§ When to write one, § The file format).

## During the session

### Challenge against the glossary

When the user uses a term that conflicts with the existing language in `docs/glossary.md`, call it out immediately. "Your glossary defines 'View' as X, but you seem to mean Y — which is it?"

### Sharpen fuzzy language

When the user uses vague or overloaded terms, propose a precise canonical term. "You're saying 'session' — do you mean the Group or the View? Those are different things."

### Discuss concrete scenarios

When domain relationships are being discussed, stress-test them with specific scenarios. Invent scenarios that probe edge cases and force the user to be precise about the boundaries between concepts.

### Cross-reference with code

When the user states how something works, check whether the code agrees. If you find a contradiction, surface it: "Your code kills a View on detach, but you just said Views persist — which is right?"

### Update docs/glossary.md inline

When a term is resolved, update `docs/glossary.md` right there. Don't batch these up — capture them as they happen.

`docs/glossary.md` should be totally devoid of implementation details. Do not treat it as a spec, a scratch pad, or a repository for implementation decisions. It is a glossary and nothing else; implementation detail goes in `docs/architecture.md` or an Agent Note.
