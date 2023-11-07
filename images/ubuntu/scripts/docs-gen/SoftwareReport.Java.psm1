function Get-JavaVersionsTable {
    $javaToolcacheVersions = Get-ChildItem $env:AGENT_TOOLSDIRECTORY/Java*/* -Directory | Sort-Object { [int] $_.Name.Split(".")[0] }

    return $javaToolcacheVersions | ForEach-Object {
        $majorVersion = $_.Name.split(".")[0]
        $fullVersion = $_.Name.Replace("-", "+")
        $defaultJavaPath = $env:JAVA_HOME
        $javaPath = Get-Item [System.Environment]::GetEnvironmentVariable("JAVA_HOME_${majorVersion}_$(Get-Arch 'X64' 'arm64')")

        $defaultPostfix = ($javaPath.Value -eq $defaultJavaPath) ? " (default)" : ""

        [PSCustomObject] @{
            "Version"              = $fullVersion + $defaultPostfix
            "Environment Variable" = $javaPath.Name
        }
    }
}
