#!/usr/bin/env bash
# run-all-tests.sh — Main test runner

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source test utils
source test-utils.sh

# Parse args
VERBOSE="${VERBOSE:-0}"
KEEP_TEST_DIR="${KEEP_TEST_DIR:-0}"
RUN_SPECIFIC="${1:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose) VERBOSE=1; shift ;;
    -k|--keep) KEEP_TEST_DIR=1; shift ;;
    -h|--help)
      echo "Usage: $0 [-v|--verbose] [-k|--keep] [test-suite]"
      echo ""
      echo "Options:"
      echo "  -v, --verbose    Verbose output"
      echo "  -k, --keep      Keep test artifacts"
      echo "  -h, --help      Show this help"
      echo ""
      echo "Test suites (if specified, run only this suite):"
      echo "  integration      Integration tests"
      echo "  edge-cases      Edge case tests"
      echo "  regression      Regression tests"
      exit 0 ;;
    *) RUN_SPECIFIC="$1"; shift ;;
  esac
done

# Setup
setup_test_env

echo "========================================="
echo "  brain-dump v0.1 Test Suite"
echo "========================================="
echo ""

if [[ "$VERBOSE" -eq 1 ]]; then
  echo "Test directory: $TEST_DIR"
  echo "Keep artifacts: $KEEP_TEST_DIR"
  echo ""
fi

# Run tests
if [[ "$RUN_SPECIFIC" == "integration" ]]; then
  source tests-integration.sh
elif [[ "$RUN_SPECIFIC" == "edge-cases" ]]; then
  source tests-edge-cases.sh
elif [[ "$RUN_SPECIFIC" == "regression" ]]; then
  source tests-regression.sh
else
  # Run all suites
  reset_counters
  source tests-integration.sh

  reset_counters
  source tests-edge-cases.sh

  reset_counters
  source tests-regression.sh
fi

# Cleanup
teardown_test_env

# Final summary
echo ""
print_summary

# Exit with failure count
exit $TESTS_FAILED
