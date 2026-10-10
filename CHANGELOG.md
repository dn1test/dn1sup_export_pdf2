# Changelog (Лог изменений)

Лог изменений **DN1Sup Export PDF 2** (`dn1sup_export_pdf2`).
Формат версий соответствует правилам `MAJOR.MINOR.PATCH`.

## [2.18.1] — 2026-10-09

- feat: publish for Extension Store - registrar ex.id, registry.json, pack tool + release workflow; docs: PUBLISHING.md + README link
- feat(frontend): add spell check with nspell and shared DN1SUP menu singleton
- Refactor: use Dn1sup.common_menu instead of global variables
- feat: nest Export PDF 2 menu inside shared DN1SUP menu, bump version to 2.16.0
- refactor!: rename package dn1c_export_pdf2 to dn1sup_export_pdf2 (v2.15.0)
- fix(project): prefer server-supplied stadia over empty local list
- feat(history): add SKP backup link tracking and open from history
- feat: add workflow rate and frame overlay flags, widen param zone boxes
- refactor(ui): move font and margin controls into template settings editor header
- fix(template): remove visibility checkbox from parameter cards and bump version to 2.13.1
- feat: remove project status field and rebuild frontend bundle
- fix: persist frame overlay flag before switching scenes to prevent autosave reset
- fix(dn1c_export_pdf2): fix recursive drop callback in useDragSort causing TypeError
- feat(ui): remove font weight/width controls and send fixed defaults
- feat(ui): switch interface font to Roboto Condensed and rebuild assets
- fix(export-pdf2): move zone badge to second card row and bump version to 2.12.5
- feat(templates): add workflow.version_rev parameter and rework template settings editor layout
- feat(project): rework workflow fields with rate/time auto-calculation and plain input styles
- feat: add scenes margin setting, rework header layout, skip master template for empty page type
- fix(ui): refine select styling, scene table widths, and label texts; bump version to 2.9.6
