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

**regenerate-example-objects.R**

The package defines a function `regenerate_example_objects()` in the source that sources the script `inst/regenerate-example-objects.R`.
