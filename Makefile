.PHONY: get format analyze test labs coverage docs cli-smoke benchmark-smoke check

get:
	dart pub get

format:
	dart format --output=none --set-exit-if-changed .

analyze:
	dart analyze --fatal-infos

test:
	dart test

labs:
	dart test test/labs

coverage:
	rm -rf coverage
	dart test --coverage=coverage/raw
	dart run coverage:format_coverage --package=. --report-on=lib --in=coverage/raw --out=coverage/lcov.info --lcov --check-ignore
	dart run tool/check_coverage.dart coverage/lcov.info 80

docs:
	dart doc --output=doc/api

cli-smoke:
	dart run bin/ndjson_analyzer.dart analyze test/fixtures/events.ndjson --format=json --workers=2 --batch-size=2

benchmark-smoke:
	dart run benchmark/pipeline_benchmark.dart --events=2000 --runs=1 --workers=2

check: format analyze test cli-smoke benchmark-smoke
