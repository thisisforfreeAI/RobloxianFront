# Git setup (run these yourself)

Claude's connection to this folder can only delete files folder-wide, and Git needs to delete its own
lock and temp files, so Git is run by you. Nothing here deletes project files.
Commands are PowerShell, from the project folder.

## 0. OneDrive

The folder is inside OneDrive, which can lock files under `.git` while it syncs and cause
`index.lock` / "Permission denied" errors. Before step 1, pause syncing
(OneDrive tray icon → gear → **Pause syncing** → 2 hours). Moving the repo out of OneDrive
(for example to `C:\Dev\RobloxianFront`) avoids this permanently; that's your call.

## 1. Check the tools and that no Git process is running

```powershell
cd "C:\Users\thato\OneDrive\Desktop\RobloxianFront"
git --version
Get-Process git -ErrorAction SilentlyContinue      # should print nothing
Test-Path .git                                     # False today: this is a fresh repo
```

If `.git` exists later and Git complains about `.git\index.lock`: run `Get-Process git` first.
Only if **no** git process is listed (and no editor is running Git), remove the stale lock:
`Remove-Item .git\index.lock`. Never remove it while a git process is running.

## 2. Create the repository

```powershell
git init -b main
git config user.name                # set if empty: git config user.name "BIGJOHN"
git config user.email               # set if empty: use your GitHub noreply address
git remote add origin https://github.com/thisisforfreeAI/RobloxianFront.git
git ls-remote origin                # prints nothing while the GitHub repo is empty
```

## 3. Stage and check that nothing from the game is included

```powershell
git add -A
git status --short
git status --short --ignored | Select-String '^!!'
```

The ignored list (`!!`) must include `src/shared/GameData/`, `docs/private/` and `_to_delete/` if present.
This must print **nothing**:

```powershell
git diff --cached --name-only | Select-String -Pattern 'GameData|docs/private|RulesData|Saddle\.luau|UnitCatalog|Locked\.luau|_to_delete|assets/original|extracted|\.ogg$|\.asar$'
```

If it prints anything, stop and run `git reset` (this only unstages; it changes no files), then tell Claude.

## 4. Commit

```powershell
git commit -m "Phase 1A: Rojo foundation, renderer, synthetic sprite pipeline"
git log --stat -1
```

## 5. Push (only when you're ready to publish; the GitHub repo is public)

```powershell
git push -u origin main
```

Never use `git reset --hard`, `git clean` or `push --force` on this repo without a specific reason.
