# Full-tool test failure root-cause analysis — 024 → 025

| 024 observed failure | Cases | Root cause and treatment in 025 |
|---|---:|---|
| `test_setup_golden.Golden.test_yes` / `test_enter_for_every_question` | 46 | All 23 expected configurations differed **only** in normalized `log`; normalization erroneously replaced substring `strata` inside filenames, while the golden recorded original log filenames. Restrict `<EXE>` substitution to engine binary paths, including CUDA-12. No application config is altered. |
| `test_setup_amd.WindowsDetection.test_prebuilt_hip_zip` | 1 | Cross-platform test on Linux had `setup.EXE=strata`, while fixture ZIP deliberately holds `strata.exe` (Windows HIP). Explicitly mock Windows executable and platform for that one Windows-only fixture. No product HIP-install behavior is relaxed. |
| `test_setup_pins.Requirements.test_an_install_from_before_the_pins_is_left_alone` | 1 | The test expected no installs from a legacy stamp, despite newly added JSON Schema stack not being in that legacy install. Require installation of `jsonschema`, `attrs`, `jsonschema-specifications`, `referencing`, `rpds-py` (and `psutil` if missing). Verify a fully installed stack is left alone. No pinned-version policy change. |
| `test_iq_pack` module import | 1 error | `add_gguf_py()` exits before unittest test discovery when llama.cpp `gguf-py` isn't installed. Mark the optional integration test module as explicitly skipped in that source-only environment. Its GGUF quantization tests were **not executed**; they must run where `gguf-py` is present. |

Additional real product-side fixes:

* `setup.cpu_info()` and `setup.cpu_floor()` leaked file handles from `/proc/cpuinfo`; now close them. `cpu_info()` previously raised `AttributeError` if `flags` was absent; both probes now use an empty set of flags rather than crash.
* `tools.canonical_xcheck.open_shard()` retained an unclosed Python file handle after creating the mmap. Now the operating system file descriptor is released deterministically while the mmap remains available until its owner closes it.

Full independent rerun: 523 unittest cases, **zero failures, zero errors, two skips** (`test_iq_pack` requires `gguf-py`; `test_setup_oldcpu` CPUID stub requires Windows). The figures mean *521 executed passes*, **not** 523 passes. Never equate these mocks to a successful GPU/model run.
