.PHONY: analyze format test check

## Flutter 静的解析
analyze:
	flutter analyze

## コードフォーマット
format:
	dart format .

## テスト実行
test:
	flutter test

## 全チェック（analyze → format → test）
check: analyze format test
