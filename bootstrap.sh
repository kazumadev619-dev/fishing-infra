#!/usr/bin/env bash
# fishing-infra/bootstrap.sh
# Pi 上で実行する。冪等。CI からは実行しない（cloudflared を壊すと
# クラスタへの到達性そのものを失うため、常に手元から適用する）。
set -euo pipefail

cd "$(dirname "$0")"

echo "==> 前提チェック"
command -v kubectl >/dev/null || { echo "kubectl が無い"; exit 1; }
command -v sops    >/dev/null || { echo "sops が無い"; exit 1; }
test -f "${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}" \
  || { echo "age 秘密鍵が見つからない"; exit 1; }

echo "==> namespace"
kubectl apply -f manifests/namespace.yaml

echo "==> ポリシー（PriorityClass / LimitRange / ResourceQuota）"
kubectl apply -f manifests/policy/

echo "==> シークレット（復号して直接 apply。平文はディスクに書かない）"
sops -d manifests/cloudflared/secret.enc.yaml | kubectl apply -f -

echo "==> cloudflared"
kubectl apply -f manifests/cloudflared/configmap.yaml
kubectl apply -f manifests/cloudflared/deployment.yaml

echo "==> redis"
kubectl apply -f manifests/redis/

echo "==> RBAC"
kubectl apply -f manifests/rbac/

echo "==> ロールアウト待ち"
kubectl -n fishing rollout status deploy/cloudflared --timeout=180s
kubectl -n fishing rollout status deploy/redis --timeout=180s

echo "==> CI 用 ServiceAccount の実効権限"
kubectl auth can-i --list --as=system:serviceaccount:fishing:ci-deployer -n fishing

echo "==> 完了"
