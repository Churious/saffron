#!/usr/bin/env bash

set -Eeuo pipefail

TEMP_DIR=""

cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        rm -rf -- "$TEMP_DIR"
    fi
}

on_error() {
    local exit_code=$?
    echo "[ERROR] Installation failed at line ${BASH_LINENO[0]} (exit ${exit_code})" >&2
    exit "$exit_code"
}

trap cleanup EXIT
trap on_error ERR

# Run as the current EC2 or CloudShell user.
if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
    echo "[ERROR] Do not run this script with sudo."
    echo "        Run it as the normal EC2 or CloudShell user."
    exit 1
fi

OS="$(uname -s)"
ARCH="$(uname -m)"

case "$OS" in
    Linux)
        KUBECTL_OS="linux"
        EKSCTL_OS="Linux"
        ;;
    Darwin)
        KUBECTL_OS="darwin"
        EKSCTL_OS="Darwin"
        ;;
    *)
        echo "[ERROR] Unsupported OS: $OS"
        exit 1
        ;;
esac

case "$ARCH" in
    x86_64|amd64)
        TOOL_ARCH="amd64"
        ;;
    aarch64|arm64)
        TOOL_ARCH="arm64"
        ;;
    *)
        echo "[ERROR] Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

for cmd in curl tar awk chmod mkdir mv ln uname mktemp; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "[ERROR] Missing required command: $cmd"
        exit 1
    }
done

if command -v sha256sum >/dev/null 2>&1; then
    CHECKSUM_COMMAND="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    CHECKSUM_COMMAND="shasum"
else
    echo "[ERROR] sha256sum or shasum is required."
    exit 1
fi

BIN_DIR="${HOME}/.local/bin"
BASHRC="${HOME}/.bashrc"
COMPLETION_DIR="${HOME}/.local/share/bash-completion/completions"

mkdir -p "$BIN_DIR" "$COMPLETION_DIR"
touch "$BASHRC"

export PATH="${BIN_DIR}:${PATH}"

ensure_line() {
    local line="$1"
    local file="$2"

    if ! grep -Fqx "$line" "$file" 2>/dev/null; then
        printf '%s\n' "$line" >>"$file"
    fi
}

verify_sha256() {
    local file="$1"
    local expected="$2"
    local actual

    if [[ "$CHECKSUM_COMMAND" == "sha256sum" ]]; then
        actual="$(sha256sum "$file" | awk '{print $1}')"
    else
        actual="$(shasum -a 256 "$file" | awk '{print $1}')"
    fi

    if [[ "$actual" != "$expected" ]]; then
        echo "[ERROR] SHA256 verification failed: $file"
        echo "        expected: $expected"
        echo "        actual:   $actual"
        exit 1
    fi
}

TEMP_DIR="$(mktemp -d)"

echo
echo "Installing tools into: ${BIN_DIR}"

# ------------------------------------------------------------
# kubectl
# ------------------------------------------------------------

echo
echo "Installing kubectl..."

KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${KUBECTL_OS}/${TOOL_ARCH}/kubectl"

curl -fsSLo "${TEMP_DIR}/kubectl" "$KUBECTL_URL"
curl -fsSLo "${TEMP_DIR}/kubectl.sha256" "${KUBECTL_URL}.sha256"

KUBECTL_EXPECTED="$(
    tr -d '[:space:]' <"${TEMP_DIR}/kubectl.sha256"
)"

verify_sha256 "${TEMP_DIR}/kubectl" "$KUBECTL_EXPECTED"

chmod 0755 "${TEMP_DIR}/kubectl"
mv "${TEMP_DIR}/kubectl" "${BIN_DIR}/kubectl"
ln -sf "${BIN_DIR}/kubectl" "${BIN_DIR}/k"

echo "kubectl installed: ${KUBECTL_VERSION}"
kubectl version --client

# ------------------------------------------------------------
# eksctl
# ------------------------------------------------------------

echo
echo "Installing eksctl..."

EKSCTL_PLATFORM="${EKSCTL_OS}_${TOOL_ARCH}"
EKSCTL_TARBALL="eksctl_${EKSCTL_PLATFORM}.tar.gz"
EKSCTL_BASE_URL="https://github.com/eksctl-io/eksctl/releases/latest/download"

curl -fsSLo "${TEMP_DIR}/${EKSCTL_TARBALL}" \
    "${EKSCTL_BASE_URL}/${EKSCTL_TARBALL}"

curl -fsSLo "${TEMP_DIR}/eksctl_checksums.txt" \
    "${EKSCTL_BASE_URL}/eksctl_checksums.txt"

EKSCTL_EXPECTED="$(
    awk -v filename="$EKSCTL_TARBALL" \
        '$2 == filename { print $1; exit }' \
        "${TEMP_DIR}/eksctl_checksums.txt"
)"

if [[ -z "$EKSCTL_EXPECTED" ]]; then
    echo "[ERROR] eksctl checksum was not found."
    exit 1
fi

verify_sha256 \
    "${TEMP_DIR}/${EKSCTL_TARBALL}" \
    "$EKSCTL_EXPECTED"

tar -xzf "${TEMP_DIR}/${EKSCTL_TARBALL}" -C "$TEMP_DIR"
install -m 0755 "${TEMP_DIR}/eksctl" "${BIN_DIR}/eksctl"

echo "eksctl installed."
eksctl version

# ------------------------------------------------------------
# Helm
# ------------------------------------------------------------

echo
echo "Installing Helm..."

curl -fsSLo "${TEMP_DIR}/get_helm.sh" \
    https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3

chmod 0755 "${TEMP_DIR}/get_helm.sh"

HELM_INSTALL_DIR="$BIN_DIR" \
USE_SUDO="false" \
    bash "${TEMP_DIR}/get_helm.sh"

echo "Helm installed."
helm version --short

# ------------------------------------------------------------
# Shell configuration
# ------------------------------------------------------------

echo
echo "Configuring PATH, aliases and completion..."

ensure_line '' "$BASHRC"
ensure_line '# Kubernetes tools' "$BASHRC"
ensure_line 'export PATH="$HOME/.local/bin:$PATH"' "$BASHRC"

while IFS= read -r alias_line; do
    ensure_line "$alias_line" "$BASHRC"
done <<'EOF'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kc='kubectl create'
alias kl='kubectl logs'
alias ka='kubectl apply'
alias kx='kubectl delete'
alias ke='kubectl edit'
EOF

kubectl completion bash >"${COMPLETION_DIR}/kubectl"
helm completion bash >"${COMPLETION_DIR}/helm"

ensure_line \
    '[[ -f "$HOME/.local/share/bash-completion/completions/kubectl" ]] && source "$HOME/.local/share/bash-completion/completions/kubectl"' \
    "$BASHRC"

ensure_line \
    '[[ -f "$HOME/.local/share/bash-completion/completions/helm" ]] && source "$HOME/.local/share/bash-completion/completions/helm"' \
    "$BASHRC"

echo
echo "========================================"
echo "Installation completed successfully"
echo "========================================"
echo
echo "Installation directory: ${BIN_DIR}"
echo
echo "Installed versions:"
kubectl version --client
eksctl version
helm version --short
echo
echo "Apply the updated shell configuration:"
echo "  source ${BASHRC}"
