# fishing-infra

Raspberry Pi 5 上の k3s クラスタで、`FishingConditionsApp`（Next.js）と
`Fishing-api`（Go・Stage 5 以降）が共有する基盤を管理するリポジトリ。

## このリポジトリが所有するもの

- namespace `fishing`（PodSecurity `restricted`）
- cloudflared（Cloudflare Tunnel）
- Redis（キャッシュ。emptyDir なので再起動で消える）
- CI 用 ServiceAccount と RBAC
- LimitRange / ResourceQuota / PriorityClass

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
