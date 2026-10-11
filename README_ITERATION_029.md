# Strata custom v0.1.39 — complete iteration 029 source delivery

Base: full iteration 028, owner's confirmed GitHub HEAD `3c7659f`.

This complete archive contains the entire Strata source tree with the new hardened multi-column IQ3_S/Q6_K/Q8_0 expert path, checked Q8_1 activation geometry and checked grouped expert/scratch buffer allocation. `include/strata/kernels/iq_launch_safety.hpp` is a standalone pure C++ arithmetic contract; tests do not require CUDA. See `docs/reports/iteration-029/` for precise details, verification and open issues. The eight personal models and Windows profiles are unmodified.

**Warning:** source-only checks do not establish real model or CUDA parity. Full Q6_K, Huihui/Unsloth Q8_0 PLE, three RCO IQ3_S, real MTP/shared and Vision are still not fully complete or proven. No build/install/test on owner hardware.

Git publication: only `docs/reports/iteration-029/PUBLISH_028_TO_029.txt`; baseline SHA prefix `3c7659f`; never stage unrelated files.
