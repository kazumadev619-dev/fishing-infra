# クラスタ実測値（2026-08-12 時点）

| 項目 | 値 |
|------|-----|
| メモリ総量 | 7.8Gi |
| メモリ空き | 6.7Gi（available） |
| CPU コア数 | 4 |
| k3s バージョン | v1.34.6+k3s1 |
| Traefik | 有効（Service `traefik` = LoadBalancer, 192.168.0.48） |
| metrics-server | 有効（`kubectl top node` が数値を返す。アイドル時 104m / 2%, 1190Mi / 14%） |
| apiserver 証明書に 127.0.0.1 | あり（SAN に `IP Address:127.0.0.1` を確認済み） |

## メモリ予算の方針

アプリ Pod のメモリ limit は (総量 - Redis 128Mi - cloudflared 128Mi - k3s/Traefik の実測) の
半分以下に収める。ローリング更新中は limit × 2 を要求するため。

- 総量: 約 7987Mi（7.8Gi）
- k3s/Traefik/coredns/metrics-server/local-path-provisioner 実測: 約 1190Mi（アイドル時）
- 差し引き: 7987 - 128(redis) - 128(cloudflared) - 1190(k3s系) ≒ 6541Mi
- この半分 ≒ 3270Mi が rolling update 時の実質上限の目安

→ 計画書 Task 7 の ResourceQuota 例（`requests.memory: 2Gi` / `limits.memory: 4Gi`、8GB モデル想定）は
このPi（7.8Gi）にそのまま適用してよい水準。

## 補足

- `/etc/rancher/k3s/config.yaml` は存在せず、既定構成のまま（`--disable=traefik` 等は未設定）。
- kubectl 実行には kubeconfig の権限修正が必要だった（`/etc/rancher/k3s/k3s.yaml` は root:root 600）。
  Pi 上で以下を実行して `~/.kube/config` に複製し `KUBECONFIG` を設定済み：
  ```bash
  mkdir -p ~/.kube
  sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
  sudo chown $(id -u):$(id -g) ~/.kube/config
  chmod 600 ~/.kube/config
  echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
  ```
