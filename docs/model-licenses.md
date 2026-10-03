# モデル重みのライセンス方針と調査メモ

## 方針（2026-10-03 オーナー決定）

**商用利用が明確に許諾されているモデル・重みだけを使う。明確でないものは不適切として採用しない。**

「明確」の基準（すべて満たすこと）:
1. 重みの配布元（公式リポジトリ・公式モデルカード）に、重みそのものへの商用可ライセンス（MIT / Apache-2.0 / CC BY 等）が明記されている
2. 第三者の再配布先のタグだけを根拠にしない
3. 学習データ起因の制約が公式に言及されていれば、それも商用利用を妨げない
4. 確認した日付・URL・ライセンス文面をこの表に記録する

## 判定表（調査日: 2026-10-03）

調査はWeb検索の要約に基づく。**一次情報（LICENSE本文）は未確認**のため、「採用可」はまだ1つもない。

| モデル | 用途 | 判定 | 根拠・懸念 |
|---|---|---|---|
| Demucs (htdemucs) 重み | 声除去 | **不採用** | 重みは「研究目的」「CC BY-NC 4.0」とする記述がある。再配布先のMITタグは基準2により根拠にならない |
| Open-Unmix `umxl` | 声除去 | **不採用** | 重みは CC BY-NC-SA 4.0（非商用） |
| Open-Unmix `umxhq` | 声除去 | 候補（要確認） | 重みはMITとされる。ただし学習データ MUSDB18-HQ の利用条件が商用を妨げないか未確認（基準3） |
| Spleeter | 声除去 | 候補（要確認） | コードはMIT。**学習済みモデルの重みのライセンス明記は未確認**（基準1）。品質はDemucsより低い |
| CREPE | ピッチ推定 | 候補（要確認） | リポジトリ・移植版ともMITとされる。一次確認が必要 |
| Whisper | 歌詞同期 | 候補（要確認） | コード・重みともMITとされる。一次確認が必要 |
| YIN | ピッチ推定 | **採用可** | 自前実装（`core/lib/src/yin.dart`）。外部重みなし |

## 運用

- 声除去モデルが確定するまで、`StemSeparator` の実装は書かない（インターフェースのみ）。
- ピッチ推定は、CREPE の確認が取れるまでYINで進める（既に実装済み）。
- 歌詞同期（Whisper）は、確認が取れるまで着手しない。
- 次の作業: 各候補の公式リポジトリで LICENSE と学習データ条件を確認し、この表を更新する。
  確認で「明確」にならなければ、商用可と明記された別モデルを探すか、自前学習を検討する。

## Sources
- [Is the `license: mit` on these weights intentional? (HTDemucs)](https://huggingface.co/adefossez/HTDemucs/discussions/1)
- [Open-Unmix (PyPI)](https://pypi.org/project/openunmix/)
- [Open-Unmix UMX-HQ (ONNX)](https://huggingface.co/edgetools/umx-hq)
- [Spleeter (JOSS)](https://joss.theoj.org/papers/10.21105/joss.02154.pdf)
- [marl/crepe](https://github.com/marl/crepe)
- [Whisper (osai-index.eu)](https://osai-index.eu/model/whisper)
