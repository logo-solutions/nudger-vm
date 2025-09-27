# devops role

Installs base packages, prepares an Ansible virtualenv, installs fzf under `/opt/fzf` and lazygit under `/opt/lazygit`, and symlinks binaries into `~/bin`.

## Requirements
- Debian/Ubuntu-like hosts
- Play should run with `become: true`

## Defaults (override as needed)
See `defaults/main.yml` for:
- `user_home`, `bin_dir`
- `ansible_venv`
- `lazygit_version` (pin or fetch latest)
- `github_token` (optional to avoid GitHub API rate limits)

## Example Play
```yaml
- hosts: all
  become: true
  roles:
    - role: devops
      vars:
        # Example: pin lazygit to a known version (skip GitHub API):
        # lazygit_version: "0.43.1"
