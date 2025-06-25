function Invoke-Git {
    param (
        [Parameter(Mandatory, Position = 0)]
        [string[]]$Arguments
    )
    & git @Arguments
}

function Rebase-AllBranchesOntoMain {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ArgumentCompleter({
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

                if (-not (Test-Path ".git")) {
                    return
                }

                git branch --format="%(refname:short)" |
                Where-Object { $_ -like "$wordToComplete*" } |
                Sort-Object |
                ForEach-Object {
                    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                }
            })]
        [string]$MainBranch = "main",
        [switch]$IncludeRemote,
        [switch]$ForcePush,
        [switch]$Interactive,
        [string]$TargetBranch

    )

    if (-not (Test-Path ".git")) {
        Write-Error "This is not a Git repository."
        return
    }

    git fetch --all

    git checkout $MainBranch
    git pull origin $MainBranch

    $branchCommand = "git branch --format='%(refname:short)'"
    if ($IncludeRemote) {
        $branchCommand = "git branch -a --format='%(refname:short)'"
    }

    # Determine branches to rebase
    if ($TargetBranch) {
        $branches = @($TargetBranch)
    } else {
        $branches = Invoke-Expression $branchCommand |
        Where-Object {
            ($_ -notmatch "->") -and
            ($_ -notmatch "^remotes/.*/$MainBranch$") -and
            ($_ -notmatch "^origin$") -and
            ($_ -notmatch "^origin/main$") -and
            ($_ -notmatch "^$MainBranch$")
        } |
        ForEach-Object {
            if ($_ -like "remotes/*") {
                $_.Replace("remotes/origin/", "")
            } else {
                $_
            }
        } |
        Sort-Object -Unique
    }

    foreach ($branch in $branches) {
        if ($Interactive) {
            $choice = Read-Host "`nDo you want to rebase branch '$branch' onto '$MainBranch'? (y/n/q)"
            $choice = $choice.ToLower()

            if ($choice -eq 'y') {
                # continue to rebase
            } elseif ($choice -eq 'n') {
                Write-Host "Skipping branch '$branch'." -ForegroundColor DarkYellow
                continue  # ✅ correctly continues the foreach loop
            } elseif ($choice -in @('q', 'quit', 'exit')) {
                Write-Host "Exiting interactive mode. Goodbye!" -ForegroundColor Cyan
                return  # ✅ exits the entire function
            } else {
                Write-Host "Invalid input. Skipping '$branch'." -ForegroundColor DarkGray
                continue
            }
        }

        try {
            Write-Host "`nChecking out branch: $branch" -ForegroundColor Cyan
            git checkout $branch

            Write-Host "Rebasing $branch onto $MainBranch with autostash..." -ForegroundColor Yellow
            git rebase $MainBranch --autostash

            if ($LASTEXITCODE -ne 0) {
                Write-Warning "❌ Rebase failed for $branch (exit code $LASTEXITCODE). Aborting rebase and continuing."
                git rebase --abort
                continue
            }

            if ($ForcePush) {
                Write-Host "Force-pushing $branch with --force-with-lease..." -ForegroundColor Magenta
                git push --force-with-lease
            }

            Write-Host "✅ $branch successfully rebased." -ForegroundColor Green
        } catch {
            Write-Warning "❌ Rebase failed for $branch. Aborting rebase and continuing."
            git rebase --abort
        }
    }

    git checkout $MainBranch
}

function Rename-GitBranch {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$NewName,

        [switch]$Push,

        [switch]$DeleteOldRemote,

        [switch]$Quiet
    )

    if (-not (Test-Path ".git")) {
        if ($Quiet) { return }
        throw "This is not a Git repository."
    }

    # Get current branch
    $currentBranch = Invoke-Git -Arguments @("rev-parse", "--abbrev-ref", "HEAD")
    if (! $currentBranch) {
        if (-not $Quiet) {
            Write-Error "Unable to determine current branch."
        }
        return
    }

    if ($currentBranch -eq $NewName) {
        if (-not $Quiet) {
            Write-Warning "Current branch name is already '$NewName'. Nothing to do."
        }
        return
    }

    # Rename the branch locally
    if (-not $Quiet) {
        Write-Host "Renaming branch '$currentBranch' to '$NewName'..." -ForegroundColor Cyan
    }
    Invoke-Git -Arguments @("branch", "-m", $NewName)

    if ($Push) {
        if (-not $Quiet) {
            Write-Host "Pushing new branch '$NewName' to origin..." -ForegroundColor Green
        }
        try {
            Invoke-Git -Arguments @("push", "-u", "origin", $NewName)
        } catch {
            if (-not $Quiet) {
                Write-Warning "Push failed: $_"
            }
        }

        if ($DeleteOldRemote) {
            if (-not $Quiet) {
                Write-Host "Deleting old remote branch '$currentBranch'..." -ForegroundColor Yellow
            }
            try {
                Invoke-Git -Arguments @("push", "origin", "--delete", $currentBranch)
            } catch {
                if (-not $Quiet) {
                    Write-Warning "Failed to delete remote branch: $_"
                }
            }
        }
    }

    if (-not $Quiet) {
        Write-Host "✅ Branch successfully renamed to '$NewName'."
    }
}

Export-ModuleMember -Function Invoke-Git
Export-ModuleMember -Function Rebase-AllBranchesOntoMain
Export-ModuleMember -Function Rename-GitBranch
