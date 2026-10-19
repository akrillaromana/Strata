# Iteration 060 local commands

List all configured personal models and their READY/PENDING state:

```powershell
.\LIST-PERSONAL-MODELS.bat
```

Qwen3.8 profiles use their `START-MODEL-*.bat` directly.

Before the first Qwen3.6-35B-A3B launch, build its isolated sidecar once:

```powershell
.\BUILD-Q36-ENGINE.bat
```

Then run any Q36 profile, for example:

```powershell
.\START-MODEL-Q36-UD-Q8-K-XL.bat
.\START-MODEL-Q36-UNCENSORED-Q8-K-XL.bat
```

A PENDING launcher intentionally refuses to start until the final GGUF(s) exist. It does not use `.part` files.

Git publication commands are supplied with the delivery response. The last confirmed published base before this work is `0c1a09f` (iteration 057), so the publication manifest is generated cumulatively from 057 to 060 unless a newer publication is confirmed by the user.
