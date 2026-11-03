# Grafana ダッシュボード

| ファイル | 内容 |
|---|---|
| `fishing-trends-infra.json` | Pi・Pod・Redis の傾向（既定で直近7日） |

## 取り込み手順（手動）

1. Grafana Cloud で Dashboards → New → Import を開く。
2. JSON ファイルをアップロードする。
3. データソースに、このスタックの Prometheus（`grafanacloud-…-prom`）を選ぶ。
4. 変更したいときは、このリポジトリの JSON を直し、同じ uid（`fishing-trends-infra`）で上書きインポートする。

## 注意

- メトリクスの保持は14日。それより長い推移はここでは見えない（ADR-005）。
- 「No data」のパネルは、Alloy の allowlist に無いメトリクス名の可能性がある。Explore で名前を確かめ、`k8s-monitoring-values.yaml` の `metricsTuning` に足すか、クエリを直す。
- アプリ側のパネル（リクエスト数・外部 API のエラー率）は、FishingConditionsApp の #283 の後に足す。
