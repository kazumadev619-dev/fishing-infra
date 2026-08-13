# fishing-infra

Raspberry Pi 5 上の k3s クラスタで、`FishingConditionsApp`（Next.js）と
`Fishing-api`（Go・Stage 5 以降）が共有する基盤を管理するリポジトリ。

> このドキュメントは Task 8 で本格的に整備する。

## リソース予算（namespace: fishing）

| ワークロード | requests.memory | limits.memory | 所有リポジトリ |
|-------------|-----------------|---------------|---------------|
| fishing-app（Next.js） | 256Mi | 512Mi | FishingConditionsApp |
| fishing-api（Go・Stage 5） | 128Mi | 256Mi | Fishing-api |
| redis | 64Mi | 128Mi | fishing-infra |
| cloudflared | 64Mi | 128Mi | fishing-infra |

ローリング更新中は対象ワークロードの limits が一時的に 2 倍必要になる。
