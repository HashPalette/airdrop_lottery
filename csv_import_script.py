#!/usr/bin/env python3
"""
CSV Import Script for Airdrop Lottery
CSVファイルを読み込んで、add_participantを1000件ずつ実行するスクリプト

Usage:
    python csv_import_script.py --csv participants.csv --lottery-id 1 --contract-address 0x123... [options]
"""

import csv
import json
import subprocess
import sys
import time
import argparse
from typing import List, Optional
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class AirdropLotteryImporter:
    def __init__(self, contract_address: str, lottery_id: int, batch_size: int = 1000, delay: float = 2.0):
        """
        Args:
            contract_address: デプロイされたコントラクトのアドレス
            lottery_id: 抽選ID
            batch_size: バッチサイズ（デフォルト1000件）
            delay: バッチ間の待機時間（秒）
        """
        self.contract_address = contract_address
        self.lottery_id = lottery_id
        self.batch_size = batch_size
        self.delay = delay
        
    def read_csv(self, csv_file: str, address_column: str = 'address') -> List[str]:
        """
        CSVファイルからアドレスを読み込む
        
        Args:
            csv_file: CSVファイルのパス
            address_column: アドレスが含まれる列名
            
        Returns:
            アドレスのリスト
        """
        addresses = []
        try:
            with open(csv_file, 'r', encoding='utf-8') as file:
                reader = csv.DictReader(file)
                for row_num, row in enumerate(reader, start=2):  # ヘッダー行を考慮して2から開始
                    address = row.get(address_column, '').strip()
                    if address:
                        if self.validate_address(address):
                            addresses.append(address)
                        else:
                            logger.warning(f"行 {row_num}: 無効なアドレス形式 '{address}' をスキップしました")
                    else:
                        logger.warning(f"行 {row_num}: アドレスが空です")
                        
            logger.info(f"CSVファイルから {len(addresses)} 件の有効なアドレスを読み込みました")
            return addresses
            
        except FileNotFoundError:
            logger.error(f"CSVファイルが見つかりません: {csv_file}")
            sys.exit(1)
        except Exception as e:
            logger.error(f"CSVファイルの読み込み中にエラーが発生しました: {e}")
            sys.exit(1)
    
    def validate_address(self, address: str) -> bool:
        """
        Aptosアドレスの基本的な検証
        
        Args:
            address: 検証するアドレス
            
        Returns:
            有効な場合True
        """
        if not address.startswith('0x'):
            return False
        
        hex_part = address[2:]
        if not hex_part:
            return False
            
        try:
            int(hex_part, 16)
            return True
        except ValueError:
            return False
    
    def create_batches(self, addresses: List[str]) -> List[List[str]]:
        """
        アドレスリストをバッチに分割
        
        Args:
            addresses: アドレスのリスト
            
        Returns:
            バッチに分割されたアドレスリスト
        """
        batches = []
        for i in range(0, len(addresses), self.batch_size):
            batch = addresses[i:i + self.batch_size]
            batches.append(batch)
        
        logger.info(f"合計 {len(addresses)} 件のアドレスを {len(batches)} バッチに分割しました（バッチサイズ: {self.batch_size}）")
        return batches
    
    def execute_add_participant(self, addresses: List[str]) -> bool:
        """
        add_participant関数を実行
        
        Args:
            addresses: 追加するアドレスのリスト
            
        Returns:
            成功した場合True
        """
        try:
            addresses_json = json.dumps(addresses)
            
            cmd = [
                'aptos', 'move', 'run',
                '--function-id', f'{self.contract_address}::airdrop_lottery::add_participant',
                '--args', f'u64:{self.lottery_id}', f'address:{addresses_json}'
            ]
            
            logger.info(f"実行中: {len(addresses)} 件のアドレスを追加...")
            logger.debug(f"コマンド: {' '.join(cmd)}")
            
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
            
            if result.returncode == 0:
                logger.info(f"✅ 成功: {len(addresses)} 件のアドレスを追加しました")
                return True
            else:
                logger.error(f"❌ エラー: add_participant実行に失敗しました")
                logger.error(f"stdout: {result.stdout}")
                logger.error(f"stderr: {result.stderr}")
                return False
                
        except subprocess.TimeoutExpired:
            logger.error("❌ タイムアウト: コマンドの実行時間が120秒を超えました")
            return False
        except Exception as e:
            logger.error(f"❌ 予期しないエラー: {e}")
            return False
    
    def import_participants(self, csv_file: str, address_column: str = 'address', dry_run: bool = False) -> None:
        """
        CSVファイルから参加者をインポート
        
        Args:
            csv_file: CSVファイルのパス
            address_column: アドレスが含まれる列名
            dry_run: True の場合、実際の実行は行わずログ出力のみ
        """
        logger.info("=== Airdrop Lottery CSV Import 開始 ===")
        logger.info(f"コントラクトアドレス: {self.contract_address}")
        logger.info(f"抽選ID: {self.lottery_id}")
        logger.info(f"バッチサイズ: {self.batch_size}")
        logger.info(f"バッチ間隔: {self.delay}秒")
        
        if dry_run:
            logger.info("🔍 DRY RUN モード: 実際の実行は行いません")
        
        addresses = self.read_csv(csv_file, address_column)
        
        if not addresses:
            logger.error("有効なアドレスが見つかりませんでした")
            return
        
        batches = self.create_batches(addresses)
        
        successful_batches = 0
        failed_batches = 0
        total_processed = 0
        
        for i, batch in enumerate(batches, 1):
            logger.info(f"\n--- バッチ {i}/{len(batches)} 処理中 ---")
            
            if dry_run:
                logger.info(f"🔍 DRY RUN: {len(batch)} 件のアドレスを処理予定")
                successful_batches += 1
                total_processed += len(batch)
            else:
                success = self.execute_add_participant(batch)
                
                if success:
                    successful_batches += 1
                    total_processed += len(batch)
                else:
                    failed_batches += 1
                    logger.error(f"バッチ {i} の処理に失敗しました")
                
                if i < len(batches):
                    logger.info(f"⏳ {self.delay}秒待機中...")
                    time.sleep(self.delay)
        
        logger.info("\n=== 処理結果サマリー ===")
        logger.info(f"成功バッチ数: {successful_batches}/{len(batches)}")
        logger.info(f"失敗バッチ数: {failed_batches}/{len(batches)}")
        logger.info(f"処理済みアドレス数: {total_processed}/{len(addresses)}")
        
        if failed_batches > 0:
            logger.warning("⚠️  一部のバッチで失敗が発生しました。ログを確認してください。")
        else:
            logger.info("🎉 すべてのバッチが正常に処理されました！")

def main():
    parser = argparse.ArgumentParser(description='Airdrop Lottery CSV Import Script')
    parser.add_argument('--csv', required=True, help='CSVファイルのパス')
    parser.add_argument('--lottery-id', type=int, required=True, help='抽選ID')
    parser.add_argument('--contract-address', required=True, help='コントラクトアドレス')
    parser.add_argument('--address-column', default='address', help='アドレス列名（デフォルト: address）')
    parser.add_argument('--batch-size', type=int, default=1000, help='バッチサイズ（デフォルト: 1000）')
    parser.add_argument('--delay', type=float, default=2.0, help='バッチ間の待機時間（秒、デフォルト: 2.0）')
    parser.add_argument('--dry-run', action='store_true', help='実際の実行は行わず、処理内容のみ表示')
    parser.add_argument('--verbose', action='store_true', help='詳細ログを表示')
    
    args = parser.parse_args()
    
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    importer = AirdropLotteryImporter(
        contract_address=args.contract_address,
        lottery_id=args.lottery_id,
        batch_size=args.batch_size,
        delay=args.delay
    )
    
    importer.import_participants(
        csv_file=args.csv,
        address_column=args.address_column,
        dry_run=args.dry_run
    )

if __name__ == '__main__':
    main()
