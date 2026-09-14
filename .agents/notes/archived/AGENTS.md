# AGENTS.md — Archived Agent Notes

Archived Agent Notes under the class directories are frozen historical snapshots, not current authority. Never edit, reformat, translate, delete, or move a sealed note; use an active Agent Note or current documentation for new decisions and facts.

The archival change may only relocate a note into `archived/{class}/`, insert an `Archived: YYYY-MM-DD` line immediately below `Status: implemented`, and repair or delete inbound links. Do not inspect, verify, or repair links out of archived notes.

A sealed note's own links are frozen with it, still pointing relative to the path it had while active. Archiving therefore breaks its links to notes that stayed in `implemented/`, and only a target that is itself archived under the mirrored class path keeps resolving. That rot is expected and left in place: the archive records history, not a navigable map. Active prose that wants a working reference points at the current owner instead.

Run `make notes` to confirm the archive metadata is intact.
