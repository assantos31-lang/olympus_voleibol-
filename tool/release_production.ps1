param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$releaseRepo = Resolve-Path (Join-Path $PSScriptRoot '..')
Push-Location $releaseRepo

try {
    $currentBranch = (git branch --show-current).Trim()
    if ($LASTEXITCODE -ne 0 -or $currentBranch -ne 'main') {
        throw 'A publicação deve ser iniciada a partir da branch main.'
    }

    $pendingChanges = git status --porcelain
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível verificar o estado do repositório.'
    }
    if ($pendingChanges) {
        throw 'Existem alterações locais não registradas. Revise e registre tudo antes de publicar.'
    }

    $releaseTag = "production-$Version"
    git fetch --tags origin
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível atualizar as versões existentes no GitHub.'
    }

    $existingTag = git tag --list $releaseTag
    if ($existingTag) {
        throw "A versão $Version já possui uma publicação de produção."
    }

    git tag -a $releaseTag -m "Produção $Version"
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível criar o marcador de produção.'
    }

    git push origin $releaseTag
    if ($LASTEXITCODE -ne 0) {
        throw 'Não foi possível enviar o marcador de produção ao GitHub.'
    }

    Write-Host "Publicação $Version iniciada no Codemagic para Apple e Android."
}
finally {
    Pop-Location
}
