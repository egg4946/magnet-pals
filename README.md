# Magnet Pals（磁石人間）

2人協力・磁力アクションパズルのプロトタイプです。現在は **P0「磁力おもちゃ」** の段階です。

## 動かし方

1. [Godot 4](https://godotengine.org/download/windows/)（標準版。.NET 版ではない方）をダウンロードして展開する。
2. Godot を起動し、「インポート」からこのフォルダの `project.godot` を開く。
3. `F5` で実行する。

## 操作（初期設定）

| | 1P（キーボード） | 2P（マウス） |
|---|---|---|
| 左右移動 | A / D | 左クリック / 右クリック |
| ジャンプ | W | サイドキー上（またはホイール上） |
| 極切り替え | S | サイドキー下（またはホイール下） |

- `F1`：調整パネル（形・入力デバイス・各種数値の変更）
- `F4`：お絵描き（自分の磁石の形を一筆書きで描く。描いた形は次回の起動時も残る）
- `R` / `Backspace`：やり直し
- `F2` / `F3`：前／次のステージ（全3ステージ。クリアすると自動で次へ）
- 2P を「キーボード 矢印」（← → ↑ ↓）やゲームパッドに切り替えることもできる

## ドキュメント

- [docs/prototype-spec.md](docs/prototype-spec.md) — P0 の仕様、磁力ルール、調整パラメータ、プレイテスト手順
- [docs/techniques.md](docs/techniques.md) — テクニック台帳

## 自動テスト

```
godot --headless --fixed-fps 120 --path . res://tests/smoke_test.tscn
godot --headless --fixed-fps 120 --path . res://tests/stage_test.tscn
```

動作確認は Godot 4.7.2 で行いました。
