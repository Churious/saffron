#!/usr/bin/env bash

set -Eeuo pipefail

trap 'echo "[ERROR] Installation failed (line $LINENO)" >&2; exit 1' ERR

# Detect OS
OS="$(uname -s)"
case "$OS" in
    Linux|Darwin) ;;
    *)
        echo "[ERROR] Unsupported OS: $OS"
        exit 1
        ;;
esac

# Detect Architecture
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)
        KUBECTL_ARCH="amd64"
        EKSCTL_ARCH="amd64"
        ;;
    aarch64|arm64)
        KUBECTL_ARCH="arm64"
        EKSCTL_ARCH="arm64"
        ;;
    *)
        echo "[ERROR] Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Check required commands
for cmd in curl tar grep sudo install sha256sum; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "[ERROR] Missing required command: $cmd"
        exit 1
    }
done

echo
echo "Installing kubectl..."

KUBECTL_VERSION="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"

curl -fsSLo kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl"

chmod +x kubectl

sudo mv kubectl /usr/bin/kubectl
sudo ln -sf /usr/bin/kubectl /usr/local/bin/k

echo "kubectl installed."
kubectl version --client

echo
echo "Installing eksctl..."

TMPDIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMPDIR"
}
trap cleanup EXIT

PLATFORM="${OS}_${EKSCTL_ARCH}"
TARBALL="eksctl_${PLATFORM}.tar.gz"
CHECKSUMS="eksctl_checksums.txt"

pushd "$TMPDIR" >/dev/null

curl -fsSLO \
    "https://github.com/eksctl-io/eksctl/releases/latest/download/${TARBALL}"

curl -fsSL \
    "https://github.com/eksctl-io/eksctl/releases/latest/download/${CHECKSUMS}" \
    -o "${CHECKSUMS}"

grep " ${TARBALL}\$" "${CHECKSUMS}" | sha256sum -c -

tar -xzf "${TARBALL}"

sudo install -m 0755 eksctl /usr/local/bin/eksctl

popd >/dev/null

echo "eksctl installed."
eksctl version

echo
echo "Installing Helm..."

curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "Generating shell completion..."

if command -v bash >/dev/null 2>&1; then
    sudo mkdir -p /etc/bash_completion.d
    sudo bash -c 'helm completion bash > /etc/bash_completion.d/helm'
fi

if command -v zsh >/dev/null 2>&1; then
    if [ -n "${fpath:-}" ]; then
        sudo mkdir -p "${fpath%% *}"
        sudo sh -c "helm completion zsh > ${fpath%% *}/_helm"
    else
        echo "zsh detected but \$fpath is unavailable. Skipping zsh completion."
    fi
fi

echo "Helm installed."
helm version --short

echo
echo "========================================"
echo "Installation completed successfully!"
echo "========================================"

echo
kubectl version --client
eksctl version
helm version --short
