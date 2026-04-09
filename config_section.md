## Configuration

All configurable options are at the top of `update-models.ps1` in the `$Config` block:

| Setting | Default | Description |
|---------|---------|-------------|
| CacheTTLHours | 4 | How long to use cached model data before refetching |
| MaxRetries | 3 | Number of retry attempts for API calls |
| RetryDelaySeconds | 2 | Initial delay between retries (doubles each retry) |

### Customizing Weights

The `$ScoringProfiles` block controls how models are scored for each slot. Example to prioritize SWE score more heavily for Opus:

```powershell
Opus = @{
    ...
    Weights = @{ SWE = 0.80; Ctx = 0.10; Ping = 0.00; Stability = 0.10; NimBonus = 2 }
    ...
}
```

### Customizing Model Classification

The `$ClassificationPatterns` block controls which models are classified as "heavy" or "fast". Add new patterns to catch new model releases:

```powershell
$ClassificationPatterns = @{
    Heavy = @(
        ...,  # existing patterns
        "new-model-name"  # add your pattern
    )
    ...
}
```

### Caching

The first run fetches fresh model data and saves it to `model-cache.json`. Subsequent runs within the TTL period use the cache, reducing startup time from ~30s to ~1s.

