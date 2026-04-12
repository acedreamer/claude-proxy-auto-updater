# Auto-Detection System Design for Claude Proxy Auto-Updater v5.0

## Vision
Eliminate manual `$ModelCaps` registry maintenance through intelligent, self-healing auto-detection that adapts to model capabilities and performance in real-time.

## Core Principles
- **Resilient but skeptical**: Graceful degradation with conservative fallbacks
- **Data-driven decisions**: Concrete metrics and thresholds drive promotions
- **Zero manual maintenance**: System self-heals and adapts automatically
- **Cross-platform consistency**: Same logic produces identical results across environments

## Architecture Overview

### Components
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Capability    │    │  Performance     │    │   Dynamic       │
│    Registry     │◄───┤    Cache         │◄───┤   Scoring       │
│  (Git-tracked)  │    │ (Git-ignored)    │    │   Engine       │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                          ┌─────────────────┐
                          │   Assignment     │
                          │     Logic        │
                          └─────────────────┘
```

### Data Flow
1. Script loads verified capabilities from `model-registry.json`
2. Combines with recent performance data from `performance-cache.json`
3. Runs real-time probes and updates performance cache
4. Calculates dynamic scores based on sliding window of performance
5. Makes role assignments using staged promotion logic
6. Writes results back to cache and updates .env

## Role Detection Logic

### Initial Classification (Cold Start)
Based on model size characteristics:
- **Fast Candidates**: <8B parameters (subject to verification)
- **Balanced Candidates**: 8B-70B parameters
- **Heavy Candidates**: >70B parameters

### Dynamic Scoring Formula
```
StabilityScore = SuccessRate / (AvgLatency × Variance)
```

### Promotion Thresholds
| Role | StabilityScore | Variance | SuccessRate |
|------|----------------|----------|-------------|
| Fast | >95% | <20% | >98% |
| Balanced | >90% | <35% | >95% |
| Heavy | >85% | No limit | >92% |

### Promotion Process
1. **Initial assignment** based on cold-start classification
2. **Probation period**: 5 successful requests during active usage
3. **Verification**: Meet all promotion thresholds for 3 consecutive runs
4. **Promotion**: Role assignment updated in performance cache

## Tool Call Detection

### Mandatory Probing Strategy
- **Primary**: Real-time tool call probe on first connection
- **Validation**: Test both positive and negative scenarios
- **Fallback**: Conservative tier-based assumptions if probe fails

### Probe Implementation
```powershell
$ToolProbeTest = @{
    message = "Get weather for Paris"
    tools = @(@{name = "get_weather"; parameters = @{location = "Paris"}})
    tool_choice = "auto"
}
```

### Result Classification
- **Pass**: Returns valid `tool_calls` with proper schema
- **Fail**: Returns no tools or invalid response
- **Unknown**: Probe timed out/inconclusive

### Fallback Logic
- **Tier 1 (S/A models)**: Assume support exists (conservative)
- **Tier 2 (<8B models)**: Assume no support unless proven

## Error Handling & Safety

### Network Failures
- **Exponential backoff**: 3-tier retry logic (2s → 5s → final attempt)
- **Graceful degradation**: Mark models as unavailable, continue execution

### API Changes & Schema Drift
- **Strict validation**: Try/catch blocks around JSON parsing
- **Raw fallback**: Flag models as `tools_supported: unknown` on format changes

### Cold Start Delays (NVIDIA NIM)
- **Progressive waiting**: Up to 60s for container warm-up
- **User feedback**: Clear logging of warming up status
- **Auto-deprioritization**: Mark as `slow_start` if exceeds timeout

## Data Schema

### model-registry.json (Git-tracked)
```json
{
  "models": {
    "nvidia/llama-3.1-70b-instruct": {
      "verifiedCapabilities": {
        "toolCallSupported": true,
        "thinkingCapable": false,
        "roleBaseline": "heavy",
        "verifiedAt": "2026-04-12T12:00:00Z"
      },
      "probeHistory": [
        {
          "timestamp": "2026-04-12T12:00:00Z",
          "result": "pass",
          "latencyMs": 250,
          "schemaVersion": "1.0"
        }
      ]
    }
  },
  "schemaVersion": "1.0"
}
```

### performance-cache.json (Git-ignored)
```json
{
  "models": {
    "nvidia/llama-3.1-70b-instruct": {
      "currentPerformance": {
        "latencyWindow": [245, 255, 240, 260],
        "successWindow": [true, true, true, true],
        "lastProbe": "2026-04-12T13:00:00Z",
        "failureCount": 0
      },
      "calculatedScores": {
        "stabilityScore": 95.8,
        "successRate": 100.0,
        "latencyVariance": 0.08
      }
    }
  },
  "lastUpdated": "2026-04-12T13:00:00Z",
  "windowSize": 10
}
```

## Implementation Phases

### Phase 1: PowerShell Implementation
- Implement auto-detection logic in `update-models.ps1`
- Utilize PowerShell 7.2+ features for optimal performance
- Establish JSON schema and file persistence

### Phase 2: JSON Schema Standardization
- Extract logic to reusable JSON consumption patterns
- Ensure cross-platform consistency through standardized schema
- Add bash script compatibility through schema consumption

### Phase 3: Unified Library (Optional)
- Move core logic to Python utility for Linux-native environments
- Maintain PowerShell and bash compatibility through utility calls

## Platform Requirements

### PowerShell Requirements
- **Minimum Version**: PowerShell 7.2 (Core)
- **Key Features**: `ForEach-Object -Parallel`, improved JSON handling
- **Shebang**: Use `#!/usr/bin/env pwsh` for cross-platform compatibility

### Bash Requirements
- **Minimum Version**: Bash 4.4+
- **Dependencies**: `jq` for JSON parsing
- **Features**: Associative arrays for in-memory capability storage

### Network Constraints
- **Timeout**: Strict 30s timeout per probe
- **Retry Logic**: Exponential backoff for network failures
- **Cold Start Awareness**: Distinguish loading state from capability failure

## Success Metrics

### Primary Metrics
- **Manual maintenance eliminated**: 100% reduction in `$ModelCaps` registry edits
- **Auto-detection accuracy**: >95% correct role assignments
- **Performance stability**: <5% variance in latency across runs

### Secondary Metrics
- **Error recovery time**: <60s from probe failure to graceful degradation
- **Cold start handling**: <60s for NVIDIA NIM warm-up detection
- **Cross-platform consistency**: Identical results on Windows/Linux/macOS

---

**Design Approved**: ✅ All sections reviewed and approved by user
**Next Step**: Implementation planning via writing-plans skill