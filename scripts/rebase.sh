# 1) Récupère le remote
git fetch origin

# 2) Rebase ta branche locale sur le remote
git rebase origin/feat/20250903-alban
# → s’il y a des conflits : édite, `git add <fichiers>`, puis :
git rebase --continue
# (recommence jusqu’à la fin du rebase)

# 3) Push
git push
