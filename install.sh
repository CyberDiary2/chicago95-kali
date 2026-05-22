#!/usr/bin/env bash
# chicago95-kali -- automated rice + pentest setup for Kali Linux XFCE
# usage: bash install.sh

set -eo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/dots" && pwd)"
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[-]\033[0m %s\n' "$*"; exit 1; }

[[ $EUID -eq 0 ]] && die "do not run as root"

# install apt packages one at a time -- missing names warn and skip
pkg() {
    for p in "$@"; do
        sudo apt-get install -y "$p" 2>/dev/null || warn "package not found, skipping: $p"
    done
}

# ── apt update ────────────────────────────────────────────────────────────────
apt_update() {
    log "updating apt"
    sudo apt-get update -qq
}

# ── chicago95 from github (no AUR on debian) ──────────────────────────────────
setup_chicago95() {
    log "installing chicago95 theme from github"

    local src="/tmp/Chicago95"
    [[ -d "$src" ]] && rm -rf "$src"
    git clone --depth=1 https://github.com/grassmunk/Chicago95 "$src"

    sudo mkdir -p /usr/share/themes /usr/share/icons /usr/share/fonts/chicago95

    sudo cp -r "$src/Theme/Chicago95"                    /usr/share/themes/
    sudo cp -r "$src/Icons/Chicago95"                    /usr/share/icons/
    sudo cp -r "$src/Cursors/Chicago95 Cursor Black"     /usr/share/icons/ 2>/dev/null || true
    sudo cp    "$src/Fonts/vga_font/"*.ttf               /usr/share/fonts/chicago95/ 2>/dev/null || true
    sudo fc-cache -f
    rm -rf "$src"

    # ms core fonts for accuracy
    pkg ttf-mscorefonts-installer || true

    log "chicago95 files installed -- run ./apply-theme.sh from inside XFCE to activate"
}

# ── dotfiles ──────────────────────────────────────────────────────────────────
deploy_dots() {
    log "deploying dotfiles"

    for src in "$DOTFILES_DIR"/.*; do
        [[ "$(basename "$src")" =~ ^\.(\.)?$ ]] && continue
        dest="$HOME/$(basename "$src")"
        if [[ -e "$dest" && ! -L "$dest" ]]; then
            warn "backing up $dest -> ${dest}.bak"
            mv "$dest" "${dest}.bak"
        fi
        ln -sf "$src" "$dest"
        log "linked $(basename "$src")"
    done

    mkdir -p "$HOME/.config"
    for src in "$DOTFILES_DIR"/.config/*/; do
        name="$(basename "$src")"
        dest="$HOME/.config/$name"
        if [[ -e "$dest" && ! -L "$dest" ]]; then
            warn "backing up $dest -> ${dest}.bak"
            mv "$dest" "${dest}.bak"
        fi
        ln -sf "$src" "$dest"
        log "linked .config/$name"
    done
}

# ── base tools ────────────────────────────────────────────────────────────────
install_base() {
    log "installing base tools"
    pkg git curl wget jq tmux neovim \
        python3 python3-pip pipx \
        golang ruby \
        net-tools iproute2 whois dnsutils \
        nmap tcpdump wireshark tshark \
        proxychains4 socat netcat-openbsd \
        openssl \
        unzip p7zip-full \
        ripgrep fd-find bat \
        xclip xdotool
}

# ── extra pentest tools (kali ships most already) ─────────────────────────────
install_pentest() {
    log "installing extra pentest tools"

    # kali already has: nmap, sqlmap, nikto, hydra, john, hashcat, metasploit,
    # aircrack-ng, gobuster, wfuzz, wireshark, exploitdb, theharvester, recon-ng
    # install only what's not in the default kali install
    pkg feroxbuster \
        whatweb \
        wafw00f \
        seclists \
        wordlists \
        evil-winrm \
        burpsuite

    # dalfox (xss scanner) -- not in kali repos
    if ! command -v dalfox &>/dev/null; then
        local ver
        ver=$(curl -sf https://api.github.com/repos/hahwul/dalfox/releases/latest | jq -r .tag_name)
        wget -q "https://github.com/hahwul/dalfox/releases/download/${ver}/dalfox_linux_amd64.tar.gz" \
            -O /tmp/dalfox.tar.gz
        tar -xzf /tmp/dalfox.tar.gz -C /tmp/
        sudo mv /tmp/dalfox /usr/local/bin/
        rm -f /tmp/dalfox.tar.gz
        log "dalfox installed"
    fi

    # xsstrike
    if [[ ! -d /opt/XSStrike ]]; then
        sudo git clone https://github.com/s0md3v/XSStrike /opt/XSStrike
        sudo pip3 install -r /opt/XSStrike/requirements.txt -q
        echo '#!/bin/bash\npython3 /opt/XSStrike/xsstrike.py "$@"' | sudo tee /usr/local/bin/xsstrike > /dev/null
        sudo chmod +x /usr/local/bin/xsstrike
        log "xsstrike installed"
    fi

    # pwncat-cs
    pipx install pwncat-cs 2>/dev/null || warn "pwncat-cs install failed, skipping"
}

# ── go-based tools ────────────────────────────────────────────────────────────
install_go_tools() {
    log "installing go tools"
    export GOPATH="$HOME/go"
    export PATH="$PATH:$GOPATH/bin"

    declare -A go_tools=(
        ["subfinder"]="github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
        ["httpx"]="github.com/projectdiscovery/httpx/cmd/httpx@latest"
        ["dnsx"]="github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
        ["nuclei"]="github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest"
        ["katana"]="github.com/projectdiscovery/katana/cmd/katana@latest"
        ["interactsh-client"]="github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest"
        ["notify"]="github.com/projectdiscovery/notify/cmd/notify@latest"
        ["naabu"]="github.com/projectdiscovery/naabu/v2/cmd/naabu@latest"
        ["mapcidr"]="github.com/projectdiscovery/mapcidr/cmd/mapcidr@latest"
        ["gau"]="github.com/lc/gau/v2/cmd/gau@latest"
        ["waybackurls"]="github.com/tomnomnom/waybackurls@latest"
        ["anew"]="github.com/tomnomnom/anew@latest"
        ["gf"]="github.com/tomnomnom/gf@latest"
        ["qsreplace"]="github.com/tomnomnom/qsreplace@latest"
        ["unfurl"]="github.com/tomnomnom/unfurl@latest"
        ["assetfinder"]="github.com/tomnomnom/assetfinder@latest"
        ["httprobe"]="github.com/tomnomnom/httprobe@latest"
        ["hakrawler"]="github.com/hakluke/hakrawler@latest"
        ["haklistgen"]="github.com/hakluke/haklistgen@latest"
        ["ffuf"]="github.com/ffuf/ffuf/v2@latest"
    )

    for tool in "${!go_tools[@]}"; do
        log "  go install $tool"
        go install "${go_tools[$tool]}" 2>/dev/null || warn "  $tool failed, skipping"
    done

    # gf patterns
    if [[ ! -d ~/.gf ]]; then
        git clone https://github.com/1ndianl33t/Gf-Patterns ~/.gf
        log "gf patterns installed"
    fi

    nuclei -update-templates 2>/dev/null || true
}

# ── python tools ──────────────────────────────────────────────────────────────
VENV="$HOME/.venv/pentest"

install_python_tools() {
    log "creating pentest venv at $VENV"
    python3 -m venv "$VENV"
    local pip="$VENV/bin/pip"

    log "installing python libraries into venv"
    "$pip" install -q --upgrade pip
    "$pip" install -q \
        requests \
        httpx \
        beautifulsoup4 \
        lxml \
        censys \
        shodan \
        dnspython \
        paramiko \
        impacket \
        pwntools

    log "installing pipx cli tools"
    pipx install trufflehog 2>/dev/null || warn "trufflehog failed, skipping"
    pipx install arjun       2>/dev/null || warn "arjun failed, skipping"
    pipx install jwt_tool    2>/dev/null || warn "jwt_tool failed, skipping"
    pipx install uro         2>/dev/null || warn "uro failed, skipping"
}

# ── amass ─────────────────────────────────────────────────────────────────────
install_amass() {
    if command -v amass &>/dev/null; then
        log "amass already installed"
        return
    fi
    log "installing amass"
    local ver
    ver=$(curl -sf https://api.github.com/repos/owasp-amass/amass/releases/latest \
        | jq -r .tag_name)
    wget -q "https://github.com/owasp-amass/amass/releases/download/${ver}/amass_Linux_amd64.zip" \
        -O /tmp/amass.zip
    unzip -q /tmp/amass.zip -d /tmp/amass
    sudo mv /tmp/amass/amass_Linux_amd64/amass /usr/local/bin/
    rm -rf /tmp/amass /tmp/amass.zip
}

# ── wordlists ─────────────────────────────────────────────────────────────────
setup_wordlists() {
    log "setting up wordlists"
    # kali ships rockyou compressed at /usr/share/wordlists/rockyou.txt.gz
    if [[ ! -f /usr/share/wordlists/rockyou.txt ]]; then
        sudo gunzip -k /usr/share/wordlists/rockyou.txt.gz 2>/dev/null \
            || warn "rockyou not found"
    fi
    if [[ -d /usr/share/seclists && ! -L /usr/share/wordlists/seclists ]]; then
        sudo ln -sf /usr/share/seclists /usr/share/wordlists/seclists
    fi
}

# ── grub chicago95 theme ──────────────────────────────────────────────────────
setup_grub() {
    log "installing chicago95 grub theme"
    sudo mkdir -p /boot/grub/themes/chicago95
    sudo cp -r "$TOOLS_DIR/grub/chicago95/." /boot/grub/themes/chicago95/

    if grep -q '^GRUB_THEME=' /etc/default/grub; then
        sudo sed -i 's|^GRUB_THEME=.*|GRUB_THEME="/boot/grub/themes/chicago95/theme.txt"|' /etc/default/grub
    else
        echo 'GRUB_THEME="/boot/grub/themes/chicago95/theme.txt"' | sudo tee -a /etc/default/grub
    fi

    sudo sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"|' \
        /etc/default/grub

    sudo update-grub
    log "grub theme applied"
}

# ── plymouth chicago95 boot splash ────────────────────────────────────────────
setup_plymouth() {
    log "installing plymouth and chicago95 boot splash"

    pkg plymouth plymouth-themes

    sudo mkdir -p /usr/share/plymouth/themes/chicago95
    sudo cp "$TOOLS_DIR/plymouth/chicago95/chicago95.plymouth" \
            /usr/share/plymouth/themes/chicago95/
    sudo cp "$TOOLS_DIR/plymouth/chicago95/chicago95.script" \
            /usr/share/plymouth/themes/chicago95/

    sudo plymouth-set-default-theme chicago95
    sudo update-initramfs -u

    sudo sed -i 's|quiet|quiet splash|' /etc/default/grub 2>/dev/null || true

    log "plymouth chicago95 splash installed"
}

# ── lightdm chicago95 login ───────────────────────────────────────────────────
setup_lightdm() {
    log "configuring lightdm with chicago95 greeter"

    pkg lightdm lightdm-gtk-greeter

    sudo cp "$TOOLS_DIR/lightdm/lightdm-gtk-greeter.conf" \
            /etc/lightdm/lightdm-gtk-greeter.conf

    sudo systemctl enable lightdm

    log "lightdm configured"
}

# ── shell PATH additions ───────────────────────────────────────────────────────
append_path() {
    local line='export PATH="$PATH:$HOME/go/bin:$HOME/.local/bin:$HOME/.venv/pentest/bin"'
    grep -qF "$line" "$HOME/.bashrc" || echo "$line" >> "$HOME/.bashrc"
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
    log "chicago95-kali setup starting"

    apt_update
    install_base
    setup_chicago95
    deploy_dots
    install_pentest
    install_go_tools
    install_python_tools
    install_amass
    setup_wordlists
    append_path
    setup_grub
    setup_plymouth
    setup_lightdm

    log "done. reboot, log into XFCE, then run: bash apply-theme.sh"
    log "run 'nuclei -update-templates' after first launch."
}

main "$@"
