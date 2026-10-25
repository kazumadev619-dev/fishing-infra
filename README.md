# fishing-infra

Raspberry Pi 5 上の k3s クラスタで、`FishingConditionsApp`（Next.js）と
`Fishing-api`（Go・Stage 5 以降）が共有する基盤を管理するリポジトリ。

## このリポジトリが所有するもの

- namespace `fishing`（PodSecurity `restricted`）
- cloudflared（Cloudflare Tunnel）
- Redis（キャッシュ。emptyDir なので再起動で消える）
- CI 用 ServiceAccount と RBAC
- LimitRange / ResourceQuota / PriorityClass
- 監視の収集基盤（namespace `monitoring`。Alloy / node-exporter / kube-state-metrics を Grafana Cloud へ）

## アプリリポジトリが所有してはいけないもの

上記すべて。アプリリポジトリは自分の Deployment / Service / Ingress /
ConfigMap / Secret / Job のみを持つ。

## アプリリポジトリへの契約

| # | 契約 | 値 |
|---|------|-----|
| 1 | namespace | `fishing` |
| 2 | Redis | `redis.fishing.svc.cluster.local:6379`。**キー空間は論理 DB で分離する**（Next = DB 0、Go = DB 1）。アプリ内のキー接頭辞は各リポジトリの裁量 |
| 3 | Ingress | `ingressClassName: traefik` |
| 4 | DB スキーマ所有者 | **Prisma（FishingConditionsApp）が唯一の DDL 所有者**。Go は DDL を打たず `pg_dump --schema-only` から `schema.sql` を生成する |
| 5 | URL パス | `/api/auth/*` は常に Next。Go は `/api/v1/*`。`/healthz` は Next。`/*` は Next |
| 6 | リソース予算 | 下の配分表のとおり |

## リソース予算（namespace: fishing）

| ワークロード | requests.memory | limits.memory | 所有リポジトリ |
|-------------|-----------------|---------------|---------------|
| fishing-app（Next.js） | 256Mi | 512Mi | FishingConditionsApp |
| fishing-api（Go・Stage 5） | 128Mi | 256Mi | Fishing-api |
| redis | 64Mi | 128Mi | fishing-infra |
| redis-exporter（redis Pod のサイドカー） | 16Mi | 32Mi | fishing-infra |
| cloudflared | 64Mi | 128Mi | fishing-infra |

ローリング更新中は対象ワークロードの limits が一時的に 2 倍必要になる。

## bootstrap

初回、および cloudflared / Redis / RBAC を変更したときに Pi 上で実行する。

```bash
./bootstrap.sh
```

**CI からは実行しない。** cloudflared の設定を CI から壊すと、CI 自身がクラスタに
到達できなくなり、Pi への SSH でしか復旧できなくなる。

## 災害復旧

1. **アウトオブバンド経路**: Pi への SSH（LAN 内）。cloudflared の変更は必ずこの経路で
   ロールバックできる状態で行う。
2. **age 秘密鍵**: 開発者鍵はパスワードマネージャ、recovery 鍵はオフライン保管。
   両方失うと git 上の全暗号文が永久に復号不能になる。
3. **k3s を再構築した場合**: CA が変わるため、`scripts/make-kubeconfig.sh` を再実行して
   GitHub Secrets の `KUBECONFIG_B64` を更新する。
4. **CI トークンを失効させる場合**: `kubectl -n fishing delete secret ci-deployer-token`
   → `kubectl apply -f manifests/rbac/token-secret.yaml` → kubeconfig 再生成 →
   GitHub Secrets 更新。

## 監視（Grafana Cloud）

Pi 上の `monitoring` namespace に k8s-monitoring チャート（4.5.3）を入れ、Grafana Cloud
（スタック `orangesushi3092`、prod-ap-northeast-0）へ送る。方針は FishingConditionsApp の
ADR-005 と #282。

| 送るもの | 送り先 |
|---|---|
| ノードと Pod のメトリクス、redis_exporter | Prometheus |
| namespace `fishing` の Pod のログ、k8s イベント | Loki |
| アプリのトレース（Alloy の 4317 / 4318 で受ける） | OTLP gateway |

`fishing` の ResourceQuota の外（`monitoring`）で動く。Alloy は requests 128Mi / limits 512Mi。

### 初回の手順

1. トークンの Secret を作る。**Claude Code の `!` からは実行しない**（エディタが開けず、平文が会話ログに出る）。
   自分のターミナルで:

   ```bash
   sops edit manifests/monitoring/secret.enc.yaml
   ```

   開いたエディタに次を書いて保存する（`<token>` は Grafana Cloud の access policy
   `fishing-alloy` のトークン。scope は metrics:write / logs:write / traces:write）。

   ```yaml
   apiVersion: v1
   kind: Secret
   metadata:
     name: grafana-cloud
     namespace: monitoring
   type: Opaque
   stringData:
     prometheus-username: "3683143"
     loki-username: "1837236"
     otlp-username: "1879460"
     token: "<token>"
   ```

2. Pi で `./scripts/install-monitoring.sh` を実行する（helm が要る）。
3. redis_exporter のサイドカーを入れるため、`./bootstrap.sh` も流す（redis Deployment の更新）。

設定を変えたときも 2 を流せばよい（`helm upgrade --install`）。

## シークレット運用

- SOPS/age。recipients は 開発者鍵 / CI 鍵 / recovery 鍵 の 3 つ。
- 編集は `sops manifests/cloudflared/secret.enc.yaml` の in-place で行い、平文ファイルを作らない。
- recipient を増減したら `sops updatekeys <file>` で既存暗号文を更新する。
- 鍵が漏洩したら、現在値だけでなく **git 履歴上の全バージョンの値**をローテーションする。

## 疎通確認済みの経路（2026-08-13）

- `cloudflared access tcp --hostname k8s.kazuma-lab.com --url 127.0.0.1:6443` +
  `server: https://127.0.0.1:6443` の kubeconfig で `kubectl get pods -n fishing` が通ることを確認。
- service token は環境変数 `TUNNEL_SERVICE_TOKEN_ID` / `TUNNEL_SERVICE_TOKEN_SECRET` で渡す
  （`CF_ACCESS_*` という名前の環境変数は cloudflared が読まない）。
- `/api/*` の Cloudflare キャッシュ無効化ルール（`bypass-cache-api`）を作成済み。
  動作確認（`cf-cache-status` ヘッダ）はアプリデプロイ後（Task 23）に行う。
