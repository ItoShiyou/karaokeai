# KaraokeAI

手持ちの曲を端末内だけで声抜きし、画面を見ずに歌って採点する車内カラオケアプリ（Flutter / Android + iOS）。

## 構成
- `core/` 純Dart。採点（相対音程＋リズム）、遅延補正、セットリスト、ネイティブ層のインターフェース。`dart test` で検証可能。
- `app/` Flutterアプリ。取り込み・セットリスト・ポケットモード画面。

## 現状
- [x] core: 採点、遅延推定（相互相関）、ピッチ平滑化、セットリスト（テスト10件）
- [x] app: 骨格（セットリスト画面、ポケットモード画面）
- [ ] ネイティブ音声層: 低遅延 再生＋録音（Android Oboe / iOS AVAudioEngine）
- [x] 声除去: 中央定位キャンセル（DSP、重みなし）を既定として実装。ステレオWAVのみ対応
- [ ] 声除去（ML）: 商用可が明確なモデルが見つかるまで未着手
- [ ] mp3/m4a等のデコード: ネイティブ層（AVAudioFile / MediaCodec）が必要
- [x] ピッチ推定: YIN（純Dart、テスト付き）。CREPEは未着手
- [x] 取り込み時のDRM判定（`checkImportable`）
- [ ] モデル方針: 商用可が明確なものだけ採用。現状、採用可の分離モデルはなし（Demucs重みは不採用） → `docs/model-licenses.md`
- [x] 遅延補正UI（手動）、曲一覧・遅延・無料枠の永続化、無料3曲の制限
- [ ] リモコン操作、音声読み上げ、自動遅延測定の接続
- [ ] 歌詞同期、課金（in_app_purchase。無料枠の判定はcoreに実装済み）

## 開発
```
cd core && dart pub get && dart test
cd app && flutter pub get && flutter test
```
