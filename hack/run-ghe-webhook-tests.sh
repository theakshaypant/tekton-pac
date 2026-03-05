#!/usr/bin/env bash
# Script to run all GHE webhook E2E tests with real-time log output
# Usage: ./hack/run-ghe-webhook-tests.sh [filter]
#   filter: optional regex pattern to filter test names (e.g., "Push" or "PullRequest")
#
# Features:
#   - Verbose output (-v) for detailed test logs
#   - Unbuffered output (stdbuf) for real-time log visibility
#   - Color-coded test results

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
TIMEOUT="${TIMEOUT_E2E:-45m}"
VERBOSE="${VERBOSE:-true}"
if [[ "$VERBOSE" == "true" ]]; then
  GO_TEST_FLAGS="${GO_TEST_FLAGS:--v -race -failfast}"
else
  GO_TEST_FLAGS="${GO_TEST_FLAGS:--race -failfast}"
fi
TEST_DIR="./test"

# GHE webhook test functions (only tests with Webhook: true or onWebhook=true)
GHE_TESTS=(
  # Push webhook test
  "TestGithubGHEPushWebhook"

  # Pull Request webhook tests
  "TestGithubGHEPullRequestWebhook"
  "TestGithubGHEDisableCommentsOnPR"

  # Private repository webhook test
  "TestGithubGHEPullRequestPrivateRepositoryOnWebhook"

  # Incoming webhook test
  "TestGithubGHEWebhookIncoming"

  # Comment strategy webhook tests
  "TestGithubGHECommentStrategyUpdateCELErrorReplacement"
  "TestGithubGHECommentStrategyUpdateMultiplePLRs"
  "TestGithubGHECommentStrategyUpdateMarkerMatchingWithRegexChars"
)

# Print header
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}GHE Webhook Tests Runner${NC}"
echo -e "${GREEN}(Tests with Webhook: true)${NC}"
if [[ "$VERBOSE" == "true" ]]; then
  echo -e "${GREEN}Real-time logs: ENABLED${NC}"
fi
echo -e "${GREEN}========================================${NC}"
echo ""

# Apply filter if provided
FILTER="${1:-}"
if [[ -n "$FILTER" ]]; then
  echo -e "${YELLOW}Filter: $FILTER${NC}"
  FILTERED_TESTS=()
  for test in "${GHE_TESTS[@]}"; do
    if [[ "$test" =~ $FILTER ]]; then
      FILTERED_TESTS+=("$test")
    fi
  done
  GHE_TESTS=("${FILTERED_TESTS[@]}")
fi

# Display test count
echo -e "Total tests to run: ${YELLOW}${#GHE_TESTS[@]}${NC}"
echo ""

# Check if any tests to run
if [[ ${#GHE_TESTS[@]} -eq 0 ]]; then
  echo -e "${RED}No tests matched the filter: $FILTER${NC}"
  exit 1
fi

# Build test regex
TEST_REGEX=$(IFS='|'; echo "${GHE_TESTS[*]}")

# Display command
echo -e "${YELLOW}Running command:${NC}"
echo "  go test $GO_TEST_FLAGS -timeout $TIMEOUT -count=1 -tags=e2e -run \"^($TEST_REGEX)\$\" $TEST_DIR"
echo ""

# Run tests with unbuffered output for real-time logs
export GODEBUG=asynctimerchan=1
set +e  # Don't exit on error, we want to capture the exit code
stdbuf -oL -eL go test $GO_TEST_FLAGS -timeout "$TIMEOUT" -count=1 -tags=e2e -run "^($TEST_REGEX)\$" "$TEST_DIR" 2>&1 | cat
TEST_EXIT_CODE=${PIPESTATUS[0]}
set -e

# Print summary
echo ""
if [[ $TEST_EXIT_CODE -eq 0 ]]; then
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}All GHE webhook tests passed!${NC}"
  echo -e "${GREEN}========================================${NC}"
else
  echo -e "${RED}========================================${NC}"
  echo -e "${RED}Some tests failed!${NC}"
  echo -e "${RED}========================================${NC}"
  exit 1
fi
