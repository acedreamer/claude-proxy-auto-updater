class CapabilityRegistry {
    [string]$SchemaVersion = "1.0"
    [hashtable]$Models = @{}

    CapabilityRegistry() {}

    [void] LoadFromFile([string]$path) {
        if (Test-Path $path) {
            if ($global:PSVersionTable.PSVersion.Major -ge 7) {
                $data = Get-Content $path | ConvertFrom-Json -AsHashtable
            } else {
                $json = Get-Content $path -Raw | ConvertFrom-Json
                $data = @{}
                foreach ($p in $json.PSObject.Properties) {
                    $data[$p.Name] = $p.Value
                }
            }
            $this.SchemaVersion = $data.SchemaVersion
            $this.Models = $data.Models
        }
    }

    [void] SaveToFile([string]$path) {
        $data = @{
            SchemaVersion = $this.SchemaVersion
            Models = $this.Models
        }
        $data | ConvertTo-Json -Depth 10 | Out-File $path -Encoding utf8
    }

    [hashtable] GetModelCapabilities([string]$modelId) {
        return $this.Models[$modelId]
    }

    [void] UpdateModelCapabilities([string]$modelId, [hashtable]$capabilities) {
        $this.Models[$modelId] = $capabilities
    }
}