# Aptos トークンエアドロップ抽選スマートコントラクト

## 概要

このスマートコントラクトは、Aptosブロックチェーン上でトークンエアドロップの当選者を公平かつ透明に選出するための抽選システムを提供します。Aptosのオンチェーンランダムネスを活用し、高いセキュリティと信頼性を実現しています。

## 主な機能

1. **抽選の作成と管理**
   - 名前、説明、当選者数、締切時間の設定
   - 抽選の削除や締切時間の更新
2. **参加者の登録と管理**
   - ユーザー自身による参加登録
   - 管理者による参加者の追加・削除
3. **抽選の実行**
   - Aptosのオンチェーンランダムネスを利用した公平な当選者選出
   - 締切時間後のみ実行可能
4. **結果の照会**
   - 抽選の詳細情報の取得
   - 参加者リストの取得
   - 当選者リストの取得

## 使用方法

### 1. コントラクトのデプロイ

```bash
# Aptos CLIのインストール
curl -fsSL "https://aptos.dev/scripts/install_cli.py" | python3

# プロジェクトの初期化
cd airdrop_lottery
aptos init

# コントラクトのコンパイル
aptos move compile

# コントラクトのデプロイ
aptos move publish
```

### 2. 抽選の作成

```bash
aptos move run \
  --function-id <your_address>::airdrop_lottery::create_lottery \
  --args string:"NFT Airdrop" string:"Win exclusive NFTs!" u64:10 u64:1717027200
```

- 抽選名
- 説明
- 当選者数
- 締切時間（UNIXタイムスタンプ）

### 3. 抽選への参加

```bash
aptos move run \
  --function-id <your_address>::airdrop_lottery::register_participant \
  --args u64:0
```
- 抽選ID

### 4. 抽選の実行（締切後）

```bash
aptos move run \
  --function-id <your_address>::airdrop_lottery::draw_winners \
  --args u64:0
```
- 抽選ID

### 5. 結果の確認

```bash
# 抽選の詳細を確認
aptos move view \
  --function-id <your_address>::airdrop_lottery::get_lottery_details \
  --args u64:0

# 当選者リストを確認
aptos move view \
  --function-id <your_address>::airdrop_lottery::get_winners \
  --args u64:0
```

## セキュリティ検証

- Aptosの`#[randomness]`属性を活用し、予測不可能なランダムネスを実現
- Undergasing攻撃対策として大規模参加者リストへの処理分割とガス制限を実装
- 抽選作成者のみが管理機能を実行可能
- 締切時間前の抽選実行や締切後の参加を防止
- 参加者の重複登録防止、当選者の重複なし
- 適切なイベント発行とデータ整合性の確保
- コードの可読性・保守性・エラーハンドリング・ドキュメント充実
- 主要な脆弱性は検出されず、設計通りに安全に動作することを確認

## エラーコード

- `E_NOT_AUTHORIZED (1)`: 権限がありません
- `E_LOTTERY_NOT_FOUND (2)`: 抽選が見つかりません
- `E_LOTTERY_ALREADY_COMPLETED (3)`: 抽選は既に完了しています
- `E_LOTTERY_NOT_COMPLETED (4)`: 抽選はまだ完了していません
- `E_DEADLINE_NOT_REACHED (5)`: 締切時間に達していません
- `E_DEADLINE_PASSED (6)`: 締切時間を過ぎています
- `E_ALREADY_REGISTERED (7)`: 既に登録されています
- `E_INVALID_WINNER_COUNT (8)`: 無効な当選者数です
- `E_INSUFFICIENT_PARTICIPANTS (9)`: 参加者が不足しています

## ライセンス

このスマートコントラクトはMITライセンスの下で提供されています。 