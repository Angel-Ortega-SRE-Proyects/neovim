param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $NvimArgs
)

$projectDir = (Get-Location).Path
Push-Location $projectDir
try {
  & nvim @NvimArgs
} finally {
  Pop-Location
}
