# Iteration 058 — Strata 0.1.45 selective backport

Published base: `0c1a09f` (iteration 057).
Donor: `Strata-main(5).zip`, upstream project version 0.1.45.

## Integrated

- Upstream 0.1.45 HTTP/API core in `serve/server.py`, `frontend.py`, `responses.py`, `structured.py` and tokenizer integration.
- Cross-API reasoning effort, hard reasoning budgets (including Anthropic `thinking.budget_tokens`) and answer-room reservation.
- Model-card sampling when callers leave sampling unspecified; Web no longer forces the old sampling tuple until the user changes it.
- `logit_bias`, context overflow errors, chunked/body/request hardening and newer request/accounting/restart behavior.
- Tool-call parsing fixes including literal tool tags, fenced JSON calls, forced tool choice handling and tool-name compatibility.
- Optional cache-drop, CPU-affinity, keep-awake, replicas, session-save retry and image/vision elastic server helpers.
- sm_86 wide CUDA dequant path from 0.1.45 for Q4_K/Q5_K/Q6_K/IQ4_XS/Q8_0; can be disabled with `STRATA_DEQUANT_WIDE=0`.
- New upstream contract/regression tests needed by the backported server.

## Preserved / strengthened fork behavior

- Model/run JSON is immutable from the running server: POST `/config` stays read-only/fail-closed.
- Web live PCIe/MTP tuning remains RAM-only via native `TUNE` -> `TUNED` ACK.
- System prompts, custom Web sessions/presets/structured output and Prometheus/backlog remain.
- Structured schema validation stays stricter than upstream: json_schema requires `jsonschema`, max 64 KiB and depth 32, no JSON extraction from prose/code fences. Object-only root unions are accepted.
- All 25 active tuning profiles remain at `pcie-frac=0.26` and `spec-min-p=0.9`; MTP 1.0 remains available to calibration/tuning rather than becoming the default.

## Parallel requests

The fork already has real engine-level concurrency: `"parallel": N` maps to `--batch N`; the native protocol has independent slots (`BGEN/BT/BDONE/BSTOP`) and the server schedules requests into them. A single engine window supports 2..8 slots. Iteration 058 takes upstream 0.1.45 server-side slot selection, recovery, refusal retry and batch-group awareness.

The deep upstream C++ `--batch-mtp` / layer-split multi-group engine expansion is not blindly transplanted here. It touches broad native scheduling/state code that conflicts with the fork's Q6/Q8/runtime-tune engine work. On the target single RTX 3060 12 GB, parallel remains opt-in because each extra slot consumes VRAM and can reduce per-request speed.

## Verification in the build container

- 54/54 upstream reasoning/logit-bias/model-card/chunked/context/request-hardening contracts.
- 82/82 keep-awake/replicas/session-save/cache-drop/request-accounting/slots/ready-timeout contracts.
- 37/37 frontend/parser/tool-name contracts.
- 52/52 retained runconfig/system-prompt/security/Prometheus contracts.
- 28/28 Responses + strict structured-output contracts.
- 11/11 restart-waiter recovery contracts.
- 34/34 image/exif/vision elastic contracts.
- 30/30 admission/control/fatal/prompt-encoder contracts.
- 65/65 reasoning-loop/rescue/tool/slot-allocation contracts.
- 4/4 Web model-card sampling contracts.
- JS runtime-tune test: OK. Chromium live TUNE/ACK test: OK.
- Selected new parallel contracts: 11/11 (arguments/slot groups/refusal retry/concurrent slots).
- 25/25 active MTP JSON profiles: PCIe 0.26 / MTP 0.9.
- Python compile check for `serve/*.py` and `tools/strata_tokenizer.py`: OK.
- CUDA include/dependency static check: OK. No real Windows/CUDA sm_86 build was possible in this container; hardware speed claims remain unverified locally.

## Deliberately deferred

- Full 0.1.45 native `--batch-mtp`, deeper multi-GPU batch-group engine scheduling and >8 total multi-GPU slots.
- Qwen3.6-specific native engine branch and unrelated AMD/Intel/macOS kernel branches.
- Aggressive opt-in CUDA switches that upstream itself does not enable by default.

These are candidates for targeted future backports, not safe wholesale replacements for the custom Q6/Q8 engine.
