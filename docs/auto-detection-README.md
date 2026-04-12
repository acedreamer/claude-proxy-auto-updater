# Auto-Detection System Usage

The auto-detection system eliminates manual maintenance of the `$ModelCaps` registry.

## How It Works

1. **Initial Classification**: Models are classified based on size characteristics
2. **Dynamic Scoring**: Performance metrics are tracked using sliding window
3. **Staged Promotion**: Models earn roles through consistent performance
4. **Tool Probing**: Real-time tool call validation with conservative fallbacks

## Configuration

No configuration needed - the system works automatically!

## Monitoring

Check `performance-cache.json` for real-time performance metrics:
- Stability scores
- Success rates
- Latency variance
- Promotion eligibility