#!/usr/bin/env bash
# CI 用 ServiceAccount の kubeconfig を標準出力に書き出す。
# server は 127.0.0.1:6443 固定。CI 側で cloudflared access tcp が
# このポートに橋を架ける前提（k3s の apiserver 証明書は 127.0.0.1 を SAN に含む）。
set -euo pipefail

NS=fishing
SECRET=ci-deployer-token

TOKEN=$(kubectl -n "$NS" get secret "$SECRET" -o jsonpath='{.data.token}' | base64 -d)
CA=$(kubectl -n "$NS" get secret "$SECRET" -o jsonpath='{.data.ca\.crt}')

cat <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: fishing
    cluster:
      server: https://127.0.0.1:6443
      certificate-authority-data: ${CA}
users:
  - name: ci-deployer
    user:
      token: ${TOKEN}
contexts:
  - name: ci
    context:
      cluster: fishing
      user: ci-deployer
      namespace: ${NS}
current-context: ci
EOF
