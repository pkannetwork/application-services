#!/usr/bin/env bash
#
# A convenience wrapper to running the full suite of tests and checks
# required before submitting a PR.

set -eux

if [[ ! -f "$PWD/automation/lint_bash_scripts.sh" ]]
then
    echo "all_tests.sh must be executed from the root directory."
    exit 1
fi

# Test suites. These should all pass before merging.

cargo clippy --all --all-targets --all-features -- -D warnings
cargo clippy --all --all-targets --no-default-features -- -D warnings

./gradlew ktlint detekt

if [[ "$(uname -s)" == "Darwin" ]]
then
    swiftlint --strict
else
   echo "WARNING: skipping swiftlint on non-Darwin host"
fi

# Test suites. These should all pass before merging.

cargo test --all

cargo run -p sync-test

./gradlew test

if [[ "$(uname -s)" == "Darwin" ]]
then
    ./automation/run_ios_tests.sh
else
    echo "WARNING: skipping iOS tests on non-Darwin host"
fi


# Formatters. These should always succeed, but might leave
# uncomitted changes in your working directory.

cargo fmt

if [[ "$(uname -s)" == "Darwin" ]]
then
    swiftformat megazords components/*/ios --lint --swiftversion 4 
else
    echo "WARNING: skipping swiftformat on non-Darwin host"
fi
