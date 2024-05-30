<#
.SYNOPSIS
    Installs Deno apps for Windows systems.
#>

# If unable to execute due to policy rules, run
# Set-ExecutionPolicy RemoteSigned -Scope CurrentUser.

# Exit immediately if a PowerShell Cmdlet encounters an error.
$ErrorActionPreference = 'Stop'

# Show CLI help information.
Function Usage() {
    Write-Output @'
Installer script for Deno apps.

Usage: install [OPTIONS] APP

Options:
  -h, --help                Print help information
  -l, --list                List all available apps
  -u, --user                Install apps for current user
  -v, --version <VERSION>   Version of apps to install
'@
}

# Capitalize app name.
Function Capitalize($Name) {
    $Words = $Name -Replace '_',' '
    $(Get-Culture).TextInfo.ToTitleCase($Words)
}

# Downloads file to destination efficiently.
Function DownloadFile($SrcURL, $DstFile) {
    $DstDir = Split-Path -Parent $Dest
    New-Item -Force -ItemType Directory $DstDir | Out-Null

    # The progress bar updates every byte, which makes downloads slow. See
    # https://stackoverflow.com/a/43477248 for an explanation.
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -UseBasicParsing -OutFile "$DstFile" "$SrcURL"
}

# Print error message and exit script with usage error code.
Function ErrorUsage($Message) {
    Throw "Error: $Message"
    Write-Error "Run 'install --help' for usage"
    Exit 2
}

# Find or download Jq JSON parser.
Function FindJq() {
    $JqBin = $(Get-Command jq -ErrorAction SilentlyContinue).Source
    If ($JqBin) {
        Write-Output $JqBin
    }
    Else {
        $TempFile = [System.IO.Path]::GetTempFileName() -Replace '.tmp', '.exe'
        DownloadFile `
            https://github.com/jqlang/jq/releases/latest/download/jq-windows-amd64.exe `
            $TempFile
        Write-Output $TempFile
    }
}

# Find all apps inside GitHub repository.
Function FindApps($Version) {
    $Filter = '.tree[] | select(.type == \"blob\") | .path | select(startswith(\"src/\")) | select(endswith(\".ts\")) | ltrimstr(\"src/\") | rtrimstr(\".ts\")'
    $Uri = "https://api.github.com/repos/scruffaluff/deno-apps/git/trees/$Version`?recursive=true"
    $Response = Invoke-WebRequest -UseBasicParsing -Uri "$Uri"

    $JqBin = FindJq
    Write-Output "$Response" | & $JqBin --raw-output "$Filter"
}

# Print log message to stdout if logging is enabled.
Function Log($Message) {
    If (!"$Env:DENO_APPS_NOLOG") {
        Write-Output "$Message"
    }
}

# Script entrypoint.
Function Main() {
    $ArgIdx = 0
    $DestDir = ''
    $List = $False
    $Target = 'Machine'
    $Version = 'main'

    While ($ArgIdx -LT $Args[0].Count) {
        Switch ($Args[0][$ArgIdx]) {
            { $_ -In '-d', '--dest' } {
                $DestDir = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                Exit 0
            }
            { $_ -In '-h', '--help' } {
                Usage
                Exit 0
            }
            { $_ -In '-l', '--list' } {
                $List = $True
                $ArgIdx += 1
                Break
            }
            { $_ -In '-v', '--version' } {
                $Version = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
                Break
            }
            '--user' {
                $Target = 'User'
                $ArgIdx += 1
                Break
            }
            Default {
                $Name = $Args[0][$ArgIdx]
                $ArgIdx += 1
            }
        }
    }

    If ($List) {
        $Apps = FindApps "$Version"
        Write-Output $Apps
    }
    ElseIf ($Name) {
        If ($Target -Eq 'User') {
            $DestDir = "$Env:LocalAppData\Programs\DenoApps\$Name"
        }
        Else {
            $DestDir = "C:\Program Files\DenoApps\$Name"
        }
        New-Item -Force -ItemType Directory -Path $DestDir | Out-Null

        $Path = [Environment]::GetEnvironmentVariable('Path', "$Target")
        If (-Not ($Path -Like "*$DestDir*")) {
            $PrependedPath = "$DestDir" + ";$Path";

            [System.Environment]::SetEnvironmentVariable(
                'Path', "$PrependedPath", "$Target"
            )
            $Env:Path = $PrependedPath
        }

        $Apps = FindApps "$Version"
        $MatchFound = $False
        $SrcPrefix = "https://raw.githubusercontent.com/scruffaluff/deno-apps/$Version"

        ForEach ($App in $Apps) {
            If ($Name -And ("$App" -Eq "$Name")) {
                $MatchFound = $True
                Log "Installing app $Name..."

                DownloadFile "$SrcPrefix/src/$App.ps1" "$DestDir/index.ts"
                Log "Installed $(& $Name --version)."
            }
        }

        If (-Not $MatchFound) {
            Throw "Error: No app name match found for '$Name'"
        }
    }
    Else {
        ErrorUsage "App argument required"
    }
}

# Only run Main if invoked as script. Otherwise import functions as library.
If ($MyInvocation.InvocationName -NE '.') {
    Main $Args
}
