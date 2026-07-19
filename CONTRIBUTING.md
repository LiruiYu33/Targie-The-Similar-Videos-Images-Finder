# Contributing to Targie

Thanks for your interest in Targie. To keep the project's licensing clean, every contribution must be made under the project's [GPL-3.0 license](LICENSE) and pass the **Developer Certificate of Origin (DCO)** check.

## Developer Certificate of Origin (DCO)

Targie does **not** use a CLA. Instead, every commit must be signed off under the [DCO](DCO). The DCO is a lightweight per-commit statement that you have the right to submit the patch under the project's license — see [DCO](DCO) for the full text.

### How to sign off

Add a `Signed-off-by` line to every commit, using the same name and email as your `git config`:

```text
Signed-off-by: Your Name <your.email@example.com>
```

The easiest way is to pass `-s` (or `--signoff`) to `git commit`:

```bash
git commit -s -m "Your commit message"
```

You can make this the default by adding to your repo's `.git/config`:

```ini
[commit]
    gpgsign = false
[format]
    signOff = true
```

### Fixing a missing sign-off

If you forgot to sign off the latest commit:

```bash
git commit --amend --signoff
```

For multiple commits on a branch:

```bash
git rebase --signoff main
```

PRs without a DCO sign-off on every commit will not be merged.

## Licensing of contributions

By signing off your commit you agree that your contribution is licensed under **GPL-3.0-or-later**, the same license as the rest of Targie. You retain copyright on your contribution; the DCO only certifies your right to submit it.

Please keep the existing GPL-3.0 file header on any new source file you add. A template is available at the top of any existing `.swift` file in this repository — copy it and update nothing except, optionally, an additional `Copyright (C) <year> <Your Name>` line beneath the original.

## Pull request checklist

Before opening a PR:

- [ ] `swift test` passes locally.
- [ ] `./script/build_app.sh` produces a working `dist/Targie.app`.
- [ ] Every commit has a `Signed-off-by` line (`git commit -s`).
- [ ] New `.swift` files carry the GPL-3.0 file header.
- [ ] User-facing strings are added to **all supported languages** (English, Simplified Chinese, Traditional Chinese, Spanish, French, Japanese, Korean) in [Sources/SimilarVideoFinder/Support/Localization.swift](Sources/SimilarVideoFinder/Support/Localization.swift). This is enforced at compile time by `L10n.text` - omitting any language is a build error.
