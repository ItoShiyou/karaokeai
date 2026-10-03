# モデル重みのライセンス調査メモ

調査日: 2026-10-03。Web検索の要約に基づく**一次情報未確認**の暫定結果。リリース前に各リポジトリの LICENSE と配布元の条件を直接確認し、弁護士にも見せること。

| モデル | 用途 | 結果 | 商用利用 |
|---|---|---|---|
| Demucs (htdemucs) | 声除去 | **不明確・要注意**。コードはMITだが、学習済み重みは「研究目的」「CC BY-NC 4.0」とする記述があり、一部の再配布先（Hugging Face等）が付けるMITタグは根拠として弱い | **未確定。商用前提にしない** |
| CREPE | ピッチ推定 | リポジトリ・移植版ともMIT | 可と思われる（要一次確認） |
| Whisper | 歌詞同期 | コード・重みともMIT | 可と思われる（要一次確認） |
| YIN | ピッチ推定 | アルゴリズム。自前実装（`core/lib/src/yin.dart`） | 問題なし |

## 方針（2026-10-03 決定）

オーナー判断により、**Demucsの重みは商用利用可として開発を進める**。これは一次情報で確認した結果ではなく前提である。リリース前に原作者への確認または弁護士相談で裏取りすること（外れた場合は下記の対応案へ）。

## 影響と対応案

Demucsの重みが商用不可だと、企画書の中核（¥1,480の買い切りで声除去を提供）が成立しない。

1. Meta/原作者（adefossez）に商用利用を問い合わせ、書面で確認する。
2. 商用可と明示された別の分離モデルに差し替える（要調査。学習データ起因の制約も確認）。
3. 自前で学習する（学習データのライセンスも要確認。コスト大）。

`StemSeparator` インターフェースで分離器を差し替え可能にしてあるため、1〜3のどれでもアプリ側の変更は小さい。
**モデル確定までは分離の実装をプロトタイプ扱いにし、リリース判断はライセンス確認後とする。**

## Sources
- [Is the `license: mit` on these weights intentional? (HTDemucs, Hugging Face)](https://huggingface.co/adefossez/HTDemucs/discussions/1)
- [marl/crepe](https://github.com/marl/crepe)
- [CREPE pitch LiteRT](https://huggingface.co/litert-community/CREPE-pitch-LiteRT)
- [Whisper (osai-index.eu)](https://osai-index.eu/model/whisper)
- [htdemucs ft onnx export](https://stemsplit.io/blog/htdemucs-ft-onnx-export)
