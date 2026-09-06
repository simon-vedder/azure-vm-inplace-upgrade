# Releasing

1. `CHANGELOG.md`: move *Unreleased* under the new version with today's date.
2. `src/AzureInPlaceUpgrade/AzureInPlaceUpgrade.psd1`: set `ModuleVersion`; drop `Prerelease` for a
   stable release or keep it for `-preview`.
3. Run locally: `Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1`
   and `Invoke-Pester ./tests`. Both clean.
4. Commit on a branch, open the PR, merge to `main`.
5. Tag: `git tag v0.2.0 && git push origin v0.2.0`. The release workflow refuses a tag that does
   not match the manifest version, runs the analyzer and the tests, publishes to the PowerShell
   Gallery with the `PSGALLERY_API_KEY` secret and attaches `AzureInPlaceUpgrade.zip` plus the
   runbook to the GitHub release.
6. Check the Gallery listing (`Find-Module AzureInPlaceUpgrade -AllowPrerelease`) and the GitHub
   release. `deploy/main.bicep` users point `moduleVersion` at the new version; the module link
   resolves to the Gallery package by default.
7. The Gallery API key is scoped to this package and expires after a year (created 2026-09-06);
   rotate it in the repository secret `PSGALLERY_API_KEY` before then.

What never goes into a release: lab resource ids, subscription or tenant ids, SAS URLs, product
keys other than Microsoft's public KMS client setup keys.
