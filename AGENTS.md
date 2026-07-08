# Agent Instructions

- For Tizen TV emulator packaging, signing, installing, launching, or emulator-specific debugging, read and follow `.codex/skills/tizen-emulator-deploy/SKILL.md` before acting.
- When investigating app runtime behavior, startup loading failures, missing logs, or emulator input issues, use the Remote Debug Bridge from the Tizen skill first. It can collect app logs and issue allowlisted commands such as `getState`, `nav`, and `addHost` without relying on `dlog`, inspector access, or emulator text entry.
- Never print `.env` values or certificate passwords. Treat Samsung certificate files and generated `.pwd` files as secrets.
- Generated WGTs, unpacked widgets, and signing scratch files belong under ignored `build/codex-tizen-run/`.
