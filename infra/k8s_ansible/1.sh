#!/usr/bin/env bash
set -euo pipefail

BASE="roles/users-config/tasks"
mkdir -p "$BASE"

# =========================
# tasks/main.yml
# =========================
cat <<'EOF' > "$BASE/main.yml"
---
# Orchestrateur lisible + tags par blocs

- name: 00 | hygiene
  ansible.builtin.include_tasks: 00_hygiene.yml
  tags: [always, hygiene]

- name: 10 | users
  ansible.builtin.include_tasks: 10_users.yml
  tags: [users]

- name: 20 | sudo
  ansible.builtin.include_tasks: 20_sudo.yml
  tags: [sudo]

- name: 30 | ssh authorized_keys
  ansible.builtin.include_tasks: 30_ssh_authorized_keys.yml
  tags: [ssh, keys]

- name: 40 | kubeconfig
  ansible.builtin.include_tasks: 40_kube.yml
  tags: [kube]

- name: 50 | shell aliases & guard
  ansible.builtin.include_tasks: 50_shell_aliases.yml
  tags: [shell]

- name: 60 | kubectl completion
  ansible.builtin.include_tasks: 60_kubectl_completion.yml
  tags: [kubectl, completion]

- name: 70 | tools in ~/bin
  ansible.builtin.include_tasks: 70_tools_bin.yml
  tags: [tools]

- name: 80 | git clone/update
  ansible.builtin.include_tasks: 80_git_clone.yml
  tags: [git, clone]

- name: 85 | git post-clone config/fetch
  ansible.builtin.include_tasks: 85_git_postclone.yml
  tags: [git, fetch]

- name: 90 | git identity
  ansible.builtin.include_tasks: 90_git_identity.yml
  tags: [git, identity]

- name: 95 | profile autoload
  ansible.builtin.include_tasks: 95_profile_autoload.yml
  tags: [profile, shell]

- name: 99 | github ssh bootstrap
  ansible.builtin.include_tasks: 99_github_ssh.yml
  tags: [github, ssh]
EOF

# =========================
# 00_hygiene.yml
# =========================
cat <<'EOF' > "$BASE/00_hygiene.yml"
---
- name: Pre-create remote tmp for root (quiet the warning)
  become: true
  ansible.builtin.file:
    path: /tmp/.ansible-root
    state: directory
    owner: root
    group: root
    mode: "0700"
EOF

# =========================
# 10_users.yml
# =========================
cat <<'EOF' > "$BASE/10_users.yml"
---
- name: Ensure groups referenced by users_k8s exist
  ansible.builtin.group:
    name: "{{ item }}"
    state: present
  loop: "{{ users_k8s | map(attribute='groups') | select('defined') | list | flatten | unique }}"
  when: (users_k8s | length) > 0

- name: Ensure users exist with requested properties
  become: true
  ansible.builtin.user:
    name: "{{ item.name }}"
    password: "{{ item.password | default(omit) }}"
    groups: "{{ item.groups | default([]) | join(',') }}"
    shell: /bin/bash
    create_home: true
    state: present
  loop: "{{ users_k8s }}"

- name: Pre-create remote tmp for managed users (after user creation)
  become: true
  ansible.builtin.file:
    path: "/tmp/.ansible-{{ item.name }}"
    state: directory
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0700"
  loop: "{{ users_k8s }}"
EOF

# =========================
# 20_sudo.yml
# =========================
cat <<'EOF' > "$BASE/20_sudo.yml"
---
- name: Configure passwordless sudo when requested
  become: true
  ansible.builtin.copy:
    dest: "/etc/sudoers.d/{{ item.name }}"
    content: "{{ item.name }} ALL=(ALL) NOPASSWD:ALL\n"
    owner: root
    group: root
    mode: "0440"
    validate: "visudo -cf %s"
  loop: "{{ users_k8s }}"
  when: item.sudo_nopass | default(false)
EOF

# =========================
# 30_ssh_authorized_keys.yml
# =========================
cat <<'EOF' > "$BASE/30_ssh_authorized_keys.yml"
---
- name: Ensure ~/.ssh exists for each user
  become: true
  ansible.builtin.file:
    path: "/home/{{ item.name }}/.ssh"
    state: directory
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0700"
  loop: "{{ users_k8s }}"

- name: Add SSH authorized keys (list)
  become: true
  ansible.builtin.authorized_key:
    user: "{{ item.0.name }}"
    key: "{{ item.1 }}"
    state: present
  loop: "{{ users_k8s | subelements('ssh_public_keys', skip_missing=True) }}"
  loop_control:
    label: "{{ item.0.name }}"

- name: Add SSH authorized key (single)
  become: true
  ansible.builtin.authorized_key:
    user: "{{ item.name }}"
    key: "{{ item.ssh_public_key }}"
    state: present
  loop: "{{ users_k8s }}"
  when: item.ssh_public_key is defined and (item.ssh_public_key | length) > 0
EOF

# =========================
# 40_kube.yml
# =========================
cat <<'EOF' > "$BASE/40_kube.yml"
---
- name: Ensure ~/.kube exists
  become: true
  ansible.builtin.file:
    path: "/home/{{ item.name }}/.kube"
    state: directory
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0700"
  loop: "{{ users_k8s }}"

- name: Copy kubeconfig when provided (kubeconfig or kubeconfig_src)
  become: true
  ansible.builtin.copy:
    src: "{{ item.kubeconfig_src | default(item.kubeconfig) }}"
    dest: "/home/{{ item.name }}/.kube/config"
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0600"
    remote_src: true
  loop: "{{ users_k8s }}"
  when: (item.kubeconfig_src | default(item.kubeconfig | default(''))) | length > 0

- name: Render kubeconfig from template when requested
  become: true
  ansible.builtin.template:
    src: "kubeconfig.j2"
    dest: "/home/{{ item.name }}/.kube/config"
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0600"
  loop: "{{ users_k8s }}"
  vars:
    user_name: "{{ item.name }}"
  when: item.kubeconfig_template | default(false)

- name: Ensure KUBECONFIG in .bashrc
  become: true
  ansible.builtin.lineinfile:
    path: "/home/{{ item.name }}/.bashrc"
    regexp: "^[ \t]*export KUBECONFIG="
    line: "export KUBECONFIG=$HOME/.kube/config"
    create: true
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0644"
  loop: "{{ users_k8s }}"
EOF

# =========================
# 50_shell_aliases.yml
# =========================
cat <<'EOF' > "$BASE/50_shell_aliases.yml"
---
# Garde "shell interactif" au début du .bashrc pour éviter l'exécution non-interactive
- name: Add interactive-shell guard at top of .bashrc
  become: true
  ansible.builtin.lineinfile:
    path: "/home/{{ item.name }}/{{ bashrc_file | default('.bashrc') }}"
    insertbefore: BOF
    line: '[[ $- == *i* ]] || return'
    create: true
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0644"
  loop: "{{ users_k8s }}"

- name: Deploy bash aliases file
  become: true
  ansible.builtin.copy:
    src: "bash_aliases"
    dest: "/home/{{ item.name }}/{{ bash_aliases_file }}"
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0644"
  loop: "{{ users_k8s }}"
  when: bash_aliases_enable | default(true)

- name: Ensure .bash_aliases is sourced in .bashrc (idempotent)
  become: true
  ansible.builtin.lineinfile:
    path: "/home/{{ item.name }}/{{ bashrc_file }}"
    regexp: "^[ \t]*source\s+~/.bash_aliases"
    line: "source ~/.bash_aliases"
    create: true
    state: present
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0644"
  loop: "{{ users_k8s }}"
  when: bash_aliases_enable | default(true)
EOF

# =========================
# 60_kubectl_completion.yml
# =========================
cat <<'EOF' > "$BASE/60_kubectl_completion.yml"
---
- name: Ensure bash-completion dir exists for each user
  become: true
  ansible.builtin.file:
    path: "/home/{{ item.name }}/.local/share/bash-completion/completions"
    state: directory
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0700"
  loop: "{{ users_k8s }}"
  when: kubectl_completion_enable | default(true)

- name: Generate kubectl completion file (idempotent via creates)
  become: true
  become_user: "{{ item.name }}"
  ansible.builtin.shell: >
    kubectl completion bash > /home/{{ item.name }}/.local/share/bash-completion/completions/kubectl
  args:
    creates: "/home/{{ item.name }}/.local/share/bash-completion/completions/kubectl"
  loop: "{{ users_k8s }}"
  when: kubectl_completion_enable | default(true)
EOF

# =========================
# 70_tools_bin.yml
# =========================
cat <<'EOF' > "$BASE/70_tools_bin.yml"
---
- name: Ensure per-user ~/bin exists
  become: true
  ansible.builtin.file:
    path: "/home/{{ item.name }}/bin"
    state: directory
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0755"
  loop: "{{ users_k8s }}"

- name: Stat tool binaries on remote hosts (per user/tool pair)
  ansible.builtin.stat:
    path: "{{ item.1.src }}"
  register: tools_stat
  loop: "{{ users_k8s | product(tools_symlinks | default([])) | list }}"
  loop_control:
    label: "{{ item.0.name }} <- {{ item.1.name }}"

- name: Symlink tools into per-user ~/bin (only if src exists on remote)
  become: true
  ansible.builtin.file:
    src: "{{ item.item.1.src }}"
    dest: "/home/{{ item.item.0.name }}/bin/{{ item.item.1.name }}"
    state: link
    force: true
    owner: "{{ item.item.0.name }}"
    group: "{{ item.item.0.name }}"
  loop: "{{ tools_stat.results | default([]) }}"
  when: item.stat.exists
  loop_control:
    label: "{{ item.item.0.name }} <- {{ item.item.1.name }}"
EOF

# =========================
# 80_git_clone.yml
# =========================
cat <<'EOF' > "$BASE/80_git_clone.yml"
---
- name: Ensure git is installed
  become: true
  ansible.builtin.package:
    name: git
    state: present

- name: Add github.com to known_hosts for each user
  become: true
  become_user: "{{ item.name }}"
  ansible.builtin.known_hosts:
    path: "/home/{{ item.name }}/.ssh/known_hosts"
    name: "github.com"
    key: "github.com {{ lookup('ansible.builtin.pipe', 'ssh-keyscan -t rsa,ed25519 github.com 2>/dev/null | sort -u | awk \"{print \\$2 \\\" \\\" \\$3}\" | head -n1') }}"
    state: present
  loop: "{{ users_k8s }}"
  when: (git_known_hosts_enable | default(true))

- name: "[preflight] Verify vaulted key exists in role files"
  delegate_to: localhost
  become: false
  ansible.builtin.stat:
    path: "{{ role_path }}/files/id_deploy_nudger"
  register: vaulted_key_stat
  run_once: true
  when:
    - (git_auth_mode | default('ssh')) == 'ssh'

- name: "[preflight] Fail early if vaulted key missing"
  delegate_to: localhost
  become: false
  ansible.builtin.fail:
    msg: "roles/users-config/files/id_deploy_nudger missing. Place it or disable SSH workflow."
  when:
    - (git_auth_mode | default('ssh')) == 'ssh'
    - not vaulted_key_stat.stat.exists
  run_once: true

- name: Install per-user deploy key for GitHub (from vaulted file)
  become: true
  ansible.builtin.copy:
    src: "id_deploy_nudger"
    dest: "/home/{{ item.name }}/.ssh/id_deploy_nudger"
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0600"
    decrypt: true
  loop: "{{ users_k8s }}"
  no_log: true
  when:
    - git_auth_mode == 'ssh'
    - item.git_repos is defined
    - item.git_repos | length > 0

- name: Assert dest path is under user home
  vars:
    repo_dest: "{{ item.1.dest | default('/home/' ~ item.0.name ~ '/' ~ (item.1.dest_rel | default('repo'))) }}"
  ansible.builtin.assert:
    that:
      - repo_dest is match('^/home/' ~ item.0.name ~ '/')
    fail_msg: "dest={{ repo_dest }} n'est pas sous /home/{{ item.0.name }}/"
  loop: "{{ users_k8s | subelements('git_repos', skip_missing=True) }}"
  when: git_auth_mode == 'ssh'

- name: Ensure destination dir for each repo exists
  become: true
  vars:
    repo_dest: "{{ item.1.dest | default('/home/' ~ item.0.name ~ '/' ~ (item.1.dest_rel | default('repo'))) }}"
  ansible.builtin.file:
    path: "{{ repo_dest }}"
    state: directory
    owner: "{{ item.0.name }}"
    group: "{{ item.0.name }}"
    mode: "0755"
  loop: "{{ users_k8s | subelements('git_repos', skip_missing=True) }}"
  loop_control:
    label: "{{ item.0.name }} -> {{ item.1.repo }} to {{ repo_dest }}"

- name: Clone / update repositories via SSH deploy key
  become: true
  become_user: "{{ item.0.name }}"
  vars:
    repo_dest: "{{ item.1.dest | default('/home/' ~ item.0.name ~ '/' ~ (item.1.dest_rel | default('repo'))) }}"
  ansible.builtin.git:
    repo: "{{ item.1.repo }}"
    dest: "{{ repo_dest }}"
    version: "{{ item.1.version | default('main') }}"
    update: true
    force: true
    depth: "{{ 1 if (item.1.shallow | default(true)) else omit }}"
    recursive: "{{ item.1.submodules | default(true) }}"
    track_submodules: "{{ item.1.submodules | default(true) }}"
    key_file: "/home/{{ item.0.name }}/.ssh/id_deploy_nudger"
    accept_newhostkey: true
  loop: "{{ users_k8s | subelements('git_repos', skip_missing=True) }}"
  when: git_auth_mode == 'ssh'

- name: Clone / update repositories via HTTPS (PAT)
  become: true
  become_user: "{{ item.0.name }}"
  ansible.builtin.git:
    repo: "{{ item.1.repo }}"
    dest: "{{ item.1.dest }}"
    version: "{{ item.1.version | default('main') }}"
    update: true
    force: false
    depth: "{{ 1 if (item.1.shallow | default(true)) else omit }}"
    recursive: "{{ item.1.submodules | default(true) }}"
    track_submodules: "{{ item.1.submodules | default(true) }}"
    accept_newhostkey: true
  loop: "{{ users_k8s | subelements('git_repos', skip_missing=True) }}"
  loop_control:
    label: "{{ item.0.name }} <- {{ item.1.repo }}"
  when:
    - git_auth_mode != 'ssh'
EOF

# =========================
# 85_git_postclone.yml
# =========================
cat <<'EOF' > "$BASE/85_git_postclone.yml"
---
- name: Configure remote.origin.fetch to get all branches (git_repos)
  become: true
  become_user: "{{ item.0.name }}"
  ansible.builtin.command: >
    git -C {{ item.1.dest | default('/home/' ~ item.0.name ~ '/' ~ (item.1.dest_rel | default('repo'))) }}
    config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
  changed_when: false
  loop: "{{ users_k8s | subelements('git_repos', skip_missing=True) }}"
  loop_control:
    label: "{{ item.0.name }} -> {{ item.1.repo }}"
  when: git_auth_mode == 'ssh'

- name: Fetch all branches (prune) for each repo (git_repos)
  become: true
  become_user: "{{ item.0.name }}"
  ansible.builtin.command: >
    git -C {{ item.1.dest | default('/home/' ~ item.0.name ~ '/' ~ (item.1.dest_rel | default('repo'))) }}
    fetch --all --prune
  loop: "{{ users_k8s | subelements('git_repos', skip_missing=True) }}"
  loop_control:
    label: "{{ item.0.name }} -> {{ item.1.repo }}"
  when: git_auth_mode == 'ssh'
EOF

# =========================
# 90_git_identity.yml
# =========================
cat <<'EOF' > "$BASE/90_git_identity.yml"
---
- name: Configure global git identity per user
  become: true
  become_user: "{{ item.0.name }}"
  ansible.builtin.git_config:
    name: "{{ item.1.key }}"
    value: "{{ item.1.value }}"
    scope: global
  loop: "{{ users_k8s | subelements('git_identity', skip_missing=True) }}"
  loop_control:
    label: "{{ item.0.name }} -> {{ item.1.key }}={{ item.1.value }}"

- name: Assert SSH mode matches SSH repo URLs
  ansible.builtin.assert:
    that:
      - git_auth_mode == 'ssh'
    fail_msg: "git_auth_mode != ssh alors que repo=git@github.com:... Utilise git_auth_mode=ssh ou passe les repos en HTTPS."
  loop: "{{ users_k8s | subelements('git_repos', skip_missing=True) }}"
  loop_control:
    label: "{{ item.0.name }} <- {{ item.1.repo }}"
  when: item.1.repo is search('^git@github.com:')
EOF

# =========================
# 95_profile_autoload.yml
# =========================
cat <<'EOF' > "$BASE/95_profile_autoload.yml"
---
- name: Ensure custom profile is sourced in .bashrc (if present)
  become: true
  ansible.builtin.blockinfile:
    path: "/home/{{ item.name }}/.bashrc"
    marker: "# {mark} ANSIBLE profile_logo"
    block: |
      # Charge le profil Nudger si présent (silencieux)
      if [ -f "$HOME/nudger/config-vm/profile_logo.sh" ]; then
        # Ne rien faire en shell non-interactif
        case "$-" in *i*) . "$HOME/nudger/config-vm/profile_logo.sh";; esac
      fi
    create: true
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0644"
  loop: "{{ users_k8s }}"
EOF

# =========================
# 99_github_ssh.yml
# =========================
cat <<'EOF' > "$BASE/99_github_ssh.yml"
---
- name: Ensure ~/.ssh exists with correct perms
  become: true
  ansible.builtin.file:
    path: "/home/{{ item.name }}/.ssh"
    state: directory
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0700"
  loop: "{{ users_k8s }}"

- name: Generate ed25519 SSH key for GitHub if missing (no passphrase by default)
  become: true
  become_user: "{{ item.name }}"
  ansible.builtin.command: >
    ssh-keygen -t ed25519 -C "{{ item.name }}@{{ inventory_hostname }}"
    -f /home/{{ item.name }}/.ssh/id_vm_ed25519 -N ""
  args:
    creates: "/home/{{ item.name }}/.ssh/id_vm_ed25519"
  loop: "{{ users_k8s }}"
  tags: [github, ssh]

- name: Add github.com to known_hosts (ssh-keyscan)
  become: true
  become_user: "{{ item.name }}"
  ansible.builtin.known_hosts:
    path: "/home/{{ item.name }}/.ssh/known_hosts"
    name: "github.com"
    key: "github.com {{ lookup('ansible.builtin.pipe', 'ssh-keyscan -t rsa,ed25519 github.com 2>/dev/null | sort -u | awk \"{print \\$2 \\\" \\\" \\$3}\" | head -n1') }}"
    state: present
  loop: "{{ users_k8s }}"
  tags: [github, ssh]

- name: Create ~/.ssh/config entry for GitHub (force IdentityFile)
  become: true
  ansible.builtin.blockinfile:
    path: "/home/{{ item.name }}/.ssh/config"
    create: true
    owner: "{{ item.name }}"
    group: "{{ item.name }}"
    mode: "0600"
    marker: "# {mark} ANSIBLE github.com"
    block: |
      Host github.com
        HostName github.com
        User git
        IdentityFile ~/.ssh/id_vm_ed25519
        IdentitiesOnly yes
  loop: "{{ users_k8s }}"
  tags: [github, ssh]

- name: Push SSH public key to GitHub via gh (if authenticated)
  become: true
  become_user: "{{ item.name }}"
  ansible.builtin.shell: |
    set -e
    if gh auth status >/dev/null 2>&1; then
      gh ssh-key add -t "nudger {{ inventory_hostname }}:{{ item.name }}" ~/.ssh/id_vm_ed25519.pub >/dev/null 2>&1 || true
    fi
  args:
    executable: /bin/bash
  loop: "{{ users_k8s }}"
  when: github_auto_add_key | default(false)
  tags: [github, ssh]
EOF

echo "✅ Créé: $BASE et toutes les sous-tâches."
echo "Astuce: exécute par tags, ex. ansible-playbook ... -t github,git,shell"
