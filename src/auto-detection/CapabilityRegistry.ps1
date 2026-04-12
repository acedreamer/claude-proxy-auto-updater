# CapabilityRegistry.ps1

# PowerShell class to manage model capability registry with schema validation
class CapabilityRegistry {
    [hashtable] $Registry
    [string] $CachePath
    [hashtable] $Schema

    CapabilityRegistry([string]$cachePath) {
        $this.CachePath = $cachePath
        $this.Registry = @{}
        $this.InitSchema()
        $this.LoadRegistry()
    }

    hidden InitSchema() {
        $this.Schema = @{
            "ModelName" = "string"
            "SupportsStreaming" = "boolean"
            "SupportsVision" = "boolean"
            "MaxContextTokens" = "integer"
            "MaxOutputTokens" = "integer"
            "LatencyMs" = "integer"
            "CostPerToken" = "double"
        }
    }

    [bool] ValidateModelDefinition([hashtable]$model) {
        foreach ($key in $this.Schema.Keys) {
            if (-not $model.Contains($key)) {
                Write-Error "Missing required field: $key"
                return $false
            }
            $type = $this.Schema[$key]
            $value = $model[$key]

            switch ($type) {
                "string" { if ($value -notis [string]) { return $false } }
                "boolean" { if ($value -notis [bool]) { return $false } }
                "integer" { if ($value -notis [int] -and $value -notis [long]) { return $false } }
                "double" { if ($value -notis [double] -and $value -notis [decimal]) { return $false } }
            }
        }

        # Additional validation rules
        if ($model.MaxContextTokens -lt 0) {
            Write-Error "MaxContextTokens cannot be negative"
            return $false
        }
        if ($model.MaxOutputTokens -lt 0) {
            Write-Error "MaxOutputTokens cannot be negative"
            return $false
        }
        if ($model.LatencyMs -lt 0) {
            Write-Error "LatencyMs cannot be negative"
            return $false
        }
        if ($model.CostPerToken -lt 0) {
            Write-Error "CostPerToken cannot be negative"
            return $false
        }

        return $true
    }

    [void] AddModel([string]$modelName, [hashtable]$modelDefinition) {
        if (-not $this.ValidateModelDefinition($modelDefinition)) {
            throw "Invalid model definition for $modelName"
        }
        $this.Registry[$modelName] = $modelDefinition
    }

    [hashtable] GetModel([string]$modelName) {
        if ($this.Registry.ContainsKey($modelName)) {
            return $this.Registry[$modelName]
        }
        return $null
    }

    [hashtable[]] GetAllModels() {
        return @($this.Registry.Values)
    }

    [void] SaveRegistry() {
        # Convert hashtable to JSON and save
        $this.Registry | ConvertTo-Json -Depth 10 | Set-Content -Path $this.CachePath -Encoding UTF8
    }

    [void] LoadRegistry() {
        if (Test-Path $this.CachePath) {
            $content = Get-Content -Path $this.CachePath -Encoding UTF8 -Raw
            if ($content -ne "") {
                $json = $content | ConvertFrom-Json -Depth 10
                $this.Registry = @{}
                foreach ($key in $json.PSObject.Properties.Name) {
                    $this.Registry[$key] = $json.$key | ConvertTo-Hashtable
                }
            }
        }
    }
}

# Helper function to convert PSObject to Hashtable
function ConvertTo-Hashtable {
    param(
        [Parameter(ValueFromPipeline)]
        $InputObject
    )

    process {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IDictionary]) {
            return $InputObject
        }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @()
            foreach ($item in $InputObject) {
                $collection += ConvertTo-Hashtable -InputObject $item
            }
            return $collection
        }

        if ($InputObject -is [psobject]) {
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
            }
            return $hash
        }

        return $InputObject
    }
}

# Export functions for module
Export-ModuleMember -Function ConvertTo-Hashtable
Export-ModuleMember -Class CapabilityRegistry