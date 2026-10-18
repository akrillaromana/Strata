# Iteration 058 validation commands

```text
python -m py_compile serve/*.py tools/strata_tokenizer.py
python -m unittest -q serve.test_effort_paths serve.test_logit_bias serve.test_model_card_sampling serve.test_chunked_body serve.test_context_overflow serve.test_request_hardening
python -m unittest -q serve.test_keepawake serve.test_replicas serve.test_session_save_retry serve.test_cache_drop serve.test_request_accounting serve.test_slots serve.test_ready_timeout
python -m unittest -q serve.test_responses serve.test_structured
python -m unittest -q serve.test_restart_waiters
python -m unittest -q serve.test_images serve.test_exif_orientation serve.test_vision_busy serve.test_vision_elastic
node serve/web/test_runtime_tune.js
python serve/test_runtime_tune_browser.py
```
