[CmdletBinding()]
param(
	[switch]$Configure,
	[switch]$SkipPush,
	[switch]$DryRun,
	[string]$UserVersion
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ".."))
$configPath = Join-Path $projectRoot "itch-deploy.local.json"
$vscodeSettingsPath = Join-Path $projectRoot ".vscode\settings.json"

function Resolve-ProjectPath {
	param([Parameter(Mandatory = $true)][string]$RelativePath)

	return [System.IO.Path]::GetFullPath((Join-Path $projectRoot $RelativePath))
}

function Assert-PathWithinProject {
	param([Parameter(Mandatory = $true)][string]$Path)

	$fullPath = [System.IO.Path]::GetFullPath($Path)
	$rootWithSeparator = $projectRoot.TrimEnd("\") + "\"
	if ($fullPath -ne $projectRoot -and -not $fullPath.StartsWith($rootWithSeparator, [System.StringComparison]::OrdinalIgnoreCase)) {
		throw "Refusing to modify path outside the project: $fullPath"
	}
}

function Remove-ProjectPath {
	param([Parameter(Mandatory = $true)][string]$Path)

	$fullPath = [System.IO.Path]::GetFullPath($Path)
	Assert-PathWithinProject -Path $fullPath
	if (Test-Path -LiteralPath $fullPath) {
		Remove-Item -LiteralPath $fullPath -Recurse -Force
	}
}

function Save-DeployConfig {
	param([Parameter(Mandatory = $true)]$Config)

	$Config | ConvertTo-Json | Set-Content -LiteralPath $configPath
}

function Get-DeployConfig {
	$defaults = [ordered]@{
		exportPreset = "Web"
		outputHtml = "web-export/index.html"
		archiveZip = "build/LD59.zip"
		itchTarget = ""
	}

	if (Test-Path -LiteralPath $configPath) {
		$stored = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
		foreach ($property in $stored.PSObject.Properties) {
			$defaults[$property.Name] = $property.Value
		}
	}

	$needsItchTarget = -not $SkipPush
	if ($Configure -or ($needsItchTarget -and [string]::IsNullOrWhiteSpace($defaults.itchTarget))) {
		Write-Host "Enter your itch.io target in the form username/game:web"
		$enteredTarget = Read-Host "itch target"
		if ([string]::IsNullOrWhiteSpace($enteredTarget)) {
			throw "An itch.io target is required."
		}

		if ($enteredTarget -notmatch "^[^/\s]+/[^:\s]+:[^:\s]+$") {
			throw "Invalid itch.io target format. Expected username/game:channel"
		}

		$defaults.itchTarget = $enteredTarget
		Save-DeployConfig -Config $defaults
		Write-Host "Saved itch target to $configPath"
	}

	return $defaults
}

function Get-GodotVersionInfo {
	param([Parameter(Mandatory = $true)][string]$ExecutablePath)

	$versionOutput = & $ExecutablePath "--version" 2>$null
	if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($versionOutput)) {
		return $null
	}

	$versionText = ($versionOutput | Select-Object -First 1).ToString().Trim()
	if ($versionText -match "^(?<template>[\d\.]+\.stable)\.") {
		return [pscustomobject]@{
			Version = $versionText
			TemplateFolder = $Matches.template
		}
	}

	return $null
}

function Get-GodotExecutable {
	$candidates = New-Object System.Collections.Generic.List[string]
	$downloadsPattern = Join-Path $env:USERPROFILE "Downloads\Godot_v*-stable_win64.exe\Godot_v*_console.exe"
	$commandCandidates = @("godot4", "godot")

	if (Test-Path -LiteralPath $vscodeSettingsPath) {
		try {
			$vscodeSettings = Get-Content -LiteralPath $vscodeSettingsPath -Raw | ConvertFrom-Json
			if ($vscodeSettings."godotTools.editorPath.godot4") {
				$candidates.Add($vscodeSettings."godotTools.editorPath.godot4")
			}
		} catch {
		}
	}

	if ($env:GODOT_EXE) {
		$candidates.Add($env:GODOT_EXE)
	}

	foreach ($downloadedExe in (Get-ChildItem -Path $downloadsPattern -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)) {
		$candidates.Add($downloadedExe.FullName)
	}

	foreach ($commandName in $commandCandidates) {
		$command = Get-Command $commandName -ErrorAction SilentlyContinue
		if ($command) {
			$candidates.Add($command.Source)
		}
	}

	$seen = @{}
	foreach ($candidate in $candidates) {
		if ([string]::IsNullOrWhiteSpace($candidate) -or $seen.ContainsKey($candidate)) {
			continue
		}

		$seen[$candidate] = $true
		if (-not (Test-Path -LiteralPath $candidate)) {
			continue
		}

		$versionInfo = Get-GodotVersionInfo -ExecutablePath $candidate
		if (-not $versionInfo) {
			continue
		}

		$templatePath = Join-Path $env:APPDATA "Godot\export_templates\$($versionInfo.TemplateFolder)"
		if (Test-Path -LiteralPath $templatePath) {
			return [pscustomobject]@{
				Path = $candidate
				Version = $versionInfo.Version
				TemplatePath = $templatePath
			}
		}
	}

	throw "Could not find a Godot executable with matching export templates."
}

function Get-ButlerExecutable {
	$command = Get-Command "butler" -ErrorAction SilentlyContinue
	if ($command) {
		return $command.Source
	}

	$fallback = "C:\Program Files\butler-windows-amd64\butler.exe"
	if (Test-Path -LiteralPath $fallback) {
		return $fallback
	}

	throw "Could not find butler.exe. Install it or add it to PATH."
}

$config = Get-DeployConfig
$godot = Get-GodotExecutable
$butler = $null
if (-not $SkipPush) {
	$butler = Get-ButlerExecutable
}

$exportPreset = $config.exportPreset
$outputHtml = Resolve-ProjectPath -RelativePath $config.outputHtml
$outputDir = Split-Path -Parent $outputHtml
$archiveZip = Resolve-ProjectPath -RelativePath $config.archiveZip
$archiveDir = Split-Path -Parent $archiveZip

if (-not (Test-Path -LiteralPath (Join-Path $projectRoot "export_presets.cfg"))) {
	throw "export_presets.cfg is missing from the project root."
}

Remove-ProjectPath -Path $outputDir
if (Test-Path -LiteralPath $archiveZip) {
	Assert-PathWithinProject -Path $archiveZip
	Remove-Item -LiteralPath $archiveZip -Force
}

New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null

Write-Host "Using Godot: $($godot.Path)"
Write-Host "Godot version: $($godot.Version)"
Write-Host "Exporting preset '$exportPreset' to $outputHtml"

& $godot.Path "--headless" "--path" $projectRoot "--export-release" $exportPreset $outputHtml
if ($LASTEXITCODE -ne 0) {
	throw "Godot export failed."
}

if (-not (Test-Path -LiteralPath $outputHtml)) {
	throw "Godot export did not produce $outputHtml"
}

Write-Host "Creating archive: $archiveZip"
Compress-Archive -Path (Join-Path $outputDir "*") -DestinationPath $archiveZip -CompressionLevel Optimal -Force

if ($SkipPush) {
	Write-Host "Skipping butler push."
	Write-Host "Web build folder: $outputDir"
	Write-Host "Web build zip: $archiveZip"
	exit 0
}

$butlerArgs = @("push", $outputDir, $config.itchTarget)
if ($DryRun) {
	$butlerArgs += "--dry-run"
}
if (-not [string]::IsNullOrWhiteSpace($UserVersion)) {
	$butlerArgs += @("--userversion", $UserVersion)
}

Write-Host "Running butler: $butler $($butlerArgs -join ' ')"
& $butler @butlerArgs
if ($LASTEXITCODE -ne 0) {
	throw "butler push failed."
}

Write-Host "Upload complete."
Write-Host "If this is the first upload, set the itch.io project page type to HTML and mark the channel as playable in browser."
