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

Export-ModuleMember -Function Rebase-AllBranchesOntoMain
