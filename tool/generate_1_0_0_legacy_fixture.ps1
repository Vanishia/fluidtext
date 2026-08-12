param(
    [string]$Tag = "1.0.0",
    [string]$Output = "test/fixtures/legacy_isar_1_0_0",
    [switch]$KeepWorktree
)

$ErrorActionPreference = "Stop"

$repoRoot = (& git rev-parse --show-toplevel).Trim()
if (-not $repoRoot) {
    throw "This script must be run inside the FluidText git repository."
}

$tagExists = (& git tag --list $Tag).Trim()
if ($tagExists -ne $Tag) {
    throw "Git tag '$Tag' was not found."
}

$worktree = Join-Path $repoRoot ".dart_tool\legacy-fixture-$Tag"
$outputPath = if ([System.IO.Path]::IsPathRooted($Output)) {
    $Output
} else {
    Join-Path $repoRoot $Output
}

if (Test-Path -LiteralPath $worktree) {
    & git worktree remove --force $worktree
}

& git worktree add --detach $worktree $Tag

try {
    $toolDirectory = Join-Path $worktree "tool"
    New-Item -ItemType Directory -Force -Path $toolDirectory | Out-Null
    Copy-Item `
        -LiteralPath (Join-Path $repoRoot "tool\create_legacy_isar_fixture.dart") `
        -Destination (Join-Path $toolDirectory "create_legacy_isar_fixture.dart") `
        -Force

    Push-Location $worktree
    try {
        & flutter pub get
        & dart run tool/create_legacy_isar_fixture.dart `
            --output $outputPath `
            --source-version $Tag `
            --force
    } finally {
        Pop-Location
    }
} finally {
    if (-not $KeepWorktree) {
        & git worktree remove --force $worktree
    }
}
