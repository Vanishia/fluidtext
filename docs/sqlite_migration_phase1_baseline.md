# SQLite Migration Phase 1 Baseline Notes

Phase 1 keeps production data on the legacy Isar layout. The files in this
note define how to capture the current baseline before SQLite is enabled.

## Legacy Fixture

Generate the `1.0.0` legacy fixture from the real tag, not from the current
working tree:

```powershell
.\tool\generate_1_0_0_legacy_fixture.ps1
```

The script creates a detached worktree at tag `1.0.0`, copies
`tool/create_legacy_isar_fixture.dart` into that worktree, and writes the
fixture to:

```text
test/fixtures/legacy_isar_1_0_0/
```

The fixture manifest uses this format:

```json
{
  "format": "fluidtext.legacy_fixture",
  "sourceVersion": "1.0.0",
  "expected": {
    "books": 2,
    "bookCards": 3,
    "bookAssets": 1,
    "bookRemarks": 2
  }
}
```

## Isar Baseline

Capture a synthetic Isar repository baseline with:

```powershell
dart run tool/isar_baseline.dart --output build/reports/isar_baseline.json --cards 100,1000,10000,50000
```

The report format is `fluidtext.isar_baseline.v1`:

```json
{
  "format": "fluidtext.isar_baseline.v1",
  "generatedAt": "2026-08-12T00:00:00.000Z",
  "platform": "windows",
  "dartVersion": "...",
  "cardCounts": [100, 1000],
  "cases": [
    {
      "cards": 100,
      "books": 4,
      "metrics": {
        "seedWriteMs": 0,
        "loadBooksMs": 0,
        "loadOrderedCardIdsMs": 0,
        "loadCardsByIds100Ms": 0,
        "loadBookStatsMs": 0,
        "toggleReadMs": 0,
        "toggleFavoriteMs": 0
      }
    }
  ]
}
```

Commit baseline reports only when they represent an intentional reference
environment. Ad-hoc local runs should stay under `build/reports/`.
