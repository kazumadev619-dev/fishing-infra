#!/usr/bin/env bash
# fishing-infra/scripts/install-monitoring.sh
# Pi 上で実行する。冪等（helm upgrade --install）。CI からは実行しない。
# 前提: manifests/monitoring/secret.enc.yaml（Grafana Cloud のトークン）が作成済み。
set -euo pipefail

cd "$(dirname "$0")/.."

CHART_VERSION=4.5.3

echo "==> 前提チェック"
command -v helm >/dev/null || { echo "helm が無い"; exit 1; }
command -v sops >/dev/null || { echo "sops が無い"; exit 1; }
test -f manifests/monitoring/secret.enc.yaml \
  || { echo "manifests/monitoring/secret.enc.yaml が無い（README の監視の節を参照）"; exit 1; }

echo "==> namespace"
kubectl apply -f manifests/monitoring/namespace.yaml

echo "==> シークレット（復号して直接 apply。平文はディスクに書かない）"
sops -d manifests/monitoring/secret.enc.yaml | kubectl apply -f -

echo "==> k8s-monitoring ${CHART_VERSION}"
helm upgrade --install k8s-monitoring oci://ghcr.io/grafana/helm-charts/k8s-monitoring \
  --version "${CHART_VERSION}" \
  --namespace monitoring \
  --values manifests/monitoring/k8s-monitoring-values.yaml \
  --wait --timeout 10m

kubectl -n monitoring get pods
