# Continuous integration

| Workflow | When | What |
|---|---|---|
| `ci.yml` | every pull request, and master (not for a change of `*.md` only) | builds the compiler and runs `rc2/tests/verify.sh --no-valgrind --no-tsan` |
| `ci-full.yml` | 03:00 JST every day, and by hand (Actions, "CI full") | the whole of `verify.sh`, valgrind and ThreadSanitizer included |
| `rc2-verify.yml` | called by the two above | the steps below |
| `copilot-review.yml` | a pull request opens or is marked ready | asks Copilot for a review, if the secret `COPILOT_REVIEW_TOKEN` exists |
| `claude-code-review.yml`, `claude.yml` | | Claude review and `@claude` |

`rc2-verify.yml` installs Chez Scheme, gcc, gmp and valgrind with apt, builds the Idris 2 of the
pinned upstream commit (`setup-idris2.sh`, about 12 minutes, cached in `install/` for as long as the
pin, the script and the runner image stay), builds and installs rc2 and `libs/rc2base`
(`build-rc2.sh`, about 5 minutes), and runs `verify.sh --skip-build` from `rc2/tests`. The logs of
a failed run are kept as the artifact `verify-logs`.

The two scripts are what a person runs too; they only need `scheme` on `PATH`:

```sh
.github/ci/setup-idris2.sh      # install/ gets the pinned Idris 2 (IDRIS2_SRC_URL: where to clone from)
.github/ci/build-rc2.sh         # rc2 and rc2base
source env.sh && (cd rc2/tests && ./verify.sh --skip-build)
```

## The pinned Idris 2

`idris2-rev` holds the upstream commit that rc2 is built and tested with (the `idris2-src`
checkout, which is gitignored). To move to another: change the file, and run the three commands
above on a clean checkout. The cache key includes the file, so CI builds the new one once.

## Copilot

Copilot code review is not part of the Copilot Free plan (a trial only), so nothing here
needs it. With a plan that has it, either turn on "Automatically request Copilot code review" in
the repository rulesets, or add the secret `COPILOT_REVIEW_TOKEN` (a personal access token of a
user with Copilot, allowed to write pull requests) and `copilot-review.yml` asks for the review.
`.github/copilot-instructions.md` is what Copilot reads in both cases.
