Import-Module "$PSScriptRoot\..\GitBranchTools.psm1" -Force

Describe "Rename-GitBranch Cmdlet (with Invoke-Git mock)" {

    BeforeEach {
        # Always pretend we're in a Git repo
        Mock Test-Path { return $true } -ParameterFilter { $_ -eq ".git" }

        # Default: Current branch is 'feature/old'
        Mock Invoke-Git -ModuleName GitBranchTools -ParameterFilter { $Arguments[0] -eq 'rev-parse' } { return 'feature/old' }

        # Catch-all for other Git calls to avoid real execution
        Mock Invoke-Git -ModuleName GitBranchTools
    }

    Context "Basic Rename" {
        It "renames the current branch with -NewName" {
            Rename-GitBranch -NewName "feature/new" -Quiet

            Assert-MockCalled Invoke-Git -ModuleName GitBranchTools -ParameterFilter {
                $Arguments -join (' ') -eq 'branch -m feature/new'
            } -Times 1
        }
    }

    Context "Push without deleting old remote" {
        It "pushes the new branch if -Push is used" {
            Rename-GitBranch -NewName "feature/pushed" -Push -Quiet

            Assert-MockCalled Invoke-Git -ModuleName GitBranchTools -ParameterFilter {
                $Arguments -join (' ') -eq 'push -u origin feature/pushed'
            } -Times 1

            Assert-MockCalled Invoke-Git -ModuleName GitBranchTools -ParameterFilter {
                $Arguments -contains '--delete'
            } -Times 0
        }
    }

    Context "Push and delete old branch" {
        It "pushes new and deletes old remote branch" {
            Rename-GitBranch -NewName "feature/complete" -Push -DeleteOldRemote -Quiet

            Assert-MockCalled Invoke-Git -ModuleName GitBranchTools -ParameterFilter {
                $Arguments -join (' ') -eq 'push -u origin feature/complete'
            } -Times 1

            Assert-MockCalled Invoke-Git -ModuleName GitBranchTools -ParameterFilter {
                $Arguments -join (' ') -eq 'push origin --delete feature/old'
            } -Times 1
        }
    }

    Context "No action if branch name is the same" {
        It "skips if new name equals current" {
            Mock Invoke-Git -ParameterFilter { $Arguments[0] -eq 'rev-parse' } { return 'same-name' }

            Rename-GitBranch -NewName "same-name" -Quiet

            Assert-MockCalled Invoke-Git -ParameterFilter {
                $Arguments[0] -eq 'branch' -and $Arguments[1] -eq '-m'
            } -Times 0
        }
    }

    Context "Not a Git repo" {
        It "throws error if not in a Git repo" {
            Mock Test-Path { return $false } -ParameterFilter { $_ -eq ".git" }

            Rename-GitBranch -NewName "irrelevant" -ErrorAction Stop -Quiet
            $Error[0].Exception.Message | Should -Match "not a Git repository"
        }
    }

    Context "Handles push failure gracefully" {
        It "doesn't throw on push failure" {
            Mock Invoke-Git -ParameterFilter { $Arguments[0] -eq 'rev-parse' } { return 'feature/old' }
            Mock Invoke-Git -ParameterFilter { $Arguments[0] -eq 'push' } { throw "Push failed" }

            { Rename-GitBranch -NewName "new-branch" -Push -Quiet } | Should -Not -Throw
        }
    }
}
