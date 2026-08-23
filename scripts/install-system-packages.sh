#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "install-system-packages.sh must run as root" >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

apt_get() {
  apt-get -o Acquire::Retries=5 "$@"
}

log() {
  printf '\n[system] %s\n' "$*"
}

select_locales() {
  printf '%s\n' \
    'en_US.UTF-8 UTF-8' \
    'ja_JP.UTF-8 UTF-8' \
    > /etc/locale.gen
}

install_base_packages() {
  log "Installing development and utility packages"
  apt_get update

  # The locales package generates every enabled entry in /etc/locale.gen while
  # it is installed. Limit the selection before APT invokes that post-install
  # hook, rather than only before our explicit locale-gen call below.
  select_locales

  # Intentionally no apt-get upgrade here. Updating the tagged base image and
  # rebuilding is safer and more reproducible than upgrading every package in
  # an application layer.
  apt_get install -y --no-install-recommends \
    apt-transport-https \
    bzip2 \
    build-essential \
    ca-certificates \
    checkinstall \
    cmake \
    curl \
    dconf-cli \
    direnv \
    git \
    gnupg \
    jq \
    less \
    libbz2-dev \
    libffi-dev \
    libgdbm-dev \
    liblzma-dev \
    libncurses-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    libxml2-dev \
    libxmlsec1-dev \
    llvm \
    locales \
    make \
    openssh-client \
    pigz \
    pkg-config \
    python3-venv \
    rsync \
    software-properties-common \
    sudo \
    tk-dev \
    unzip \
    wget \
    xz-utils \
    zip \
    zstd \
    zlib1g \
    zlib1g-dev

  log "Installing desktop utilities and Japanese input support"
  apt_get install -y --no-install-recommends \
    dbus-x11 \
    emacs \
    exo-utils \
    fonts-noto-cjk \
    htop \
    ibus \
    ibus-gtk \
    ibus-gtk3 \
    ibus-gtk4 \
    ibus-mozc \
    im-config \
    language-pack-ja \
    language-selector-gnome \
    mozc-utils-gui \
    nautilus \
    nomacs \
    tmux \
    x11-xkb-utils
}

install_github_cli() {
  log "Installing GitHub CLI from GitHub's APT repository"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
  chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg

  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
    "$(dpkg --print-architecture)" \
    > /etc/apt/sources.list.d/github-cli.list

  apt_get update
  apt_get install -y --no-install-recommends gh
}

configure_passwordless_sudo() {
  log "Enabling passwordless sudo for the Kasm development user"
  printf '%s\n' 'kasm-user ALL=(ALL:ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-kasm-user
  chmod 0440 /etc/sudoers.d/90-kasm-user
  visudo -cf /etc/sudoers.d/90-kasm-user
}

configure_locales() {
  log "Generating English and Japanese UTF-8 locales"
  select_locales
  locale-gen
}

cleanup() {
  log "Cleaning APT metadata"
  apt_get clean
  rm -rf /var/lib/apt/lists/* /var/tmp/* /tmp/*
}

main() {
  install_base_packages
  install_github_cli
  configure_passwordless_sudo
  configure_locales
  cleanup
}

main "$@"
