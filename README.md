# 遠征棋 (Expedition Chess)

一款 PVE 自走棋 Roguelite。每局是一次「遠征」——透過自動戰鬥、局內棋子 / 羈絆 / 裝備 / 遺物組 build、局外營地水平成長推進。以 Godot 4.7 + GDScript 開發。

## 現況

架構規格 v0.1 已完成（`docs/game-architecture/`），標記 Ready for external review;程式實作尚未開始。

## 技術棧

- Godot 4.7 / GDScript（static typing）
- 測試:GUT 9.7.1

## 開發環境

需求:Godot 4.7。

```bash
# 取得 Godot 4.7 後,以編輯器開啟本專案（Godot 專案骨架建立後）:
# godot --path .
```

> 註:目前尚無 `project.godot`,Godot 專案骨架待建立。安裝與執行指令將於專案建立後補上。

## 文件

- 主體架構規格:[docs/game-architecture-spec.md](docs/game-architecture-spec.md)（入口索引,含 12 分章）
- 進度:[PROGRESS.md](PROGRESS.md)
- 開發約定:[CLAUDE.md](CLAUDE.md)
