## Package system files

**test/**

The package uses a number of cached objects during testing in `test/`.

The `.json` files in `inspect-example/logs` are the resulting log file from running evals in `inst/test/inspect`, e.g. with: 

```bash
inspect eval inst/test/inspect/basics.py  --model anthropic/claude-sonnet-4-5 --log-format=json
```

...or:

```bash
inspect eval test/inspect/tools.py  --model anthropic/claude-sonnet-4-5 --log-format=json
```

**dist/**

`/dist` is a bundled version of the Inspect viewer. (See [here](https://github.com/UKGovernmentBEIS/inspect_ai/blob/88d1cd98041a245c1d0cca4536d60e3244630b78/src/inspect_ai/_view/www/README.md) for more information.)

`dist/assets/index.js` carries one local patch on top of the upstream build
(#208): in `clientApi()`'s `get_log()`, the single shared `pending_log_promise`
is replaced with a per-file `pending_log_promises` Map. Upstream, any caller
requesting a log while another log's request is in flight receives that other
log's contents, which poisons the viewer's IndexedDB cache and swaps metadata
between logs in the listing. The bug only affects `.json` logs (Inspect itself
defaults to `.eval`), so it is still present upstream as of `inspect_ai`
0.3.179+ (viewer source: `meridianlabs-ai/ts-mono`, `client-api.ts`). When
porting a new viewer version, check whether upstream has fixed this; if not,
re-apply the patch by searching the new bundle for `pending_log_promise`.

**regenerate-example-objects.R**

The package defines a function `regenerate_example_objects()` in the source that sources the script `inst/regenerate-example-objects.R`.
