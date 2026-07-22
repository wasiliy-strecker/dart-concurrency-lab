# Releasing

Version `0.1.0` remains GitHub-only until the repository URL, public API, and
platform CI have been reviewed.

Before a GitHub release:

1. run `make check`, `make coverage`, and `make docs`;
2. compile the executable with `dart compile exe bin/ndjson_analyzer.dart`;
3. confirm `CHANGELOG.md` and the README input/exit contracts;
4. verify the working tree is clean;
5. create an annotated `v0.1.0` tag only after explicit release approval.

Publishing to pub.dev is a separate decision. It requires removing
`publish_to: none`, validating permanent package ownership and repository
metadata, and running `dart pub publish --dry-run` before any publication.
