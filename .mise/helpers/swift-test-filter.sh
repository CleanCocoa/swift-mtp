#!/usr/bin/env bash

set -o pipefail

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

TESTS_RUN=0
TESTS_FAILED=0
ISSUES_FOUND=0
CURRENT_FAILING_TEST=""
IN_FAILURE_CONTEXT=0

while IFS= read -r line; do
    if [[ "$line" =~ Test[[:space:]]+run[[:space:]]+with[[:space:]]+[0-9]+[[:space:]]+tests[[:space:]]+in[[:space:]]+[0-9]+[[:space:]]+suites[[:space:]]+passed[[:space:]]+after ]]; then
        echo
        echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
        echo -e "${GREEN}${BOLD}✓ ALL TESTS PASSED${NC}"
        echo -e "${GREEN}$line${NC}"
        echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
        continue
    fi

    if [[ "$line" =~ Test[[:space:]]+run.*with[[:space:]]+[0-9]+[[:space:]]+tests.*failed.*after.*seconds.*with[[:space:]]+[0-9]+[[:space:]]+issue ]]; then
        echo
        echo -e "${RED}${BOLD}════════════════════════════════════════${NC}"
        echo -e "${RED}${BOLD}TEST RUN FAILED${NC}"
        echo -e "${RED}$line${NC}"
        echo -e "${RED}Failed tests: ${TESTS_FAILED}${NC}"
        echo -e "${RED}${BOLD}════════════════════════════════════════${NC}"
        continue
    fi

    if [[ "$line" =~ ^[[:space:]]*􀟈[[:space:]]+Test.*started\. ]]; then
        continue
    fi

    if [[ "$line" =~ ^[[:space:]]*􀟈[[:space:]]+Suite.*started\. ]]; then
        continue
    fi

    if [[ "$line" =~ ^[[:space:]]*􁁛[[:space:]]+Test.*passed.*after.*seconds\. ]]; then
        ((TESTS_RUN++))
        continue
    fi

    if [[ "$line" =~ ^[[:space:]]*􁁛[[:space:]]+Suite.*passed.*after.*seconds\. ]]; then
        continue
    fi

    if [[ "$line" =~ ^[[:space:]]*􀢄[[:space:]]+Test[[:space:]]+([^[:space:]]+\(\)).*recorded.*issue.*at[[:space:]]+([^:]+):([0-9]+):([0-9]+):[[:space:]]*(.*) ]]; then
        TEST_NAME="${BASH_REMATCH[1]}"
        FILE="${BASH_REMATCH[2]}"
        LINE="${BASH_REMATCH[3]}"
        COL="${BASH_REMATCH[4]}"
        MESSAGE="${BASH_REMATCH[5]}"

        if [[ "$CURRENT_FAILING_TEST" != "$TEST_NAME" ]]; then
            echo
            echo -e "${RED}${BOLD}✗ Test Failed: ${TEST_NAME}${NC}"
            CURRENT_FAILING_TEST="$TEST_NAME"
            ((TESTS_FAILED++))
        fi

        echo -e "  ${CYAN}${FILE}:${LINE}:${COL}${NC}"
        echo -e "  ${RED}${MESSAGE}${NC}"
        ((ISSUES_FOUND++))
        IN_FAILURE_CONTEXT=1
        continue
    fi

    if [[ "$line" =~ ^[[:space:]]*􀢄[[:space:]]+Test[[:space:]]+([^[:space:]]+\(\)).*failed.*after.*seconds.*with.*([0-9]+).*issue ]]; then
        TEST_NAME="${BASH_REMATCH[1]}"
        ISSUE_COUNT="${BASH_REMATCH[2]}"

        if [[ "$CURRENT_FAILING_TEST" != "$TEST_NAME" ]]; then
            echo
            echo -e "${RED}${BOLD}✗ Test Failed: ${TEST_NAME}${NC}"
            echo -e "  ${YELLOW}${ISSUE_COUNT} issue(s)${NC}"
            ((TESTS_FAILED++))
        fi
        CURRENT_FAILING_TEST=""
        IN_FAILURE_CONTEXT=0
        continue
    fi

    if [[ "$line" =~ ^[[:space:]]*􀢄[[:space:]]+Suite[[:space:]]+\"([^\"]+)\".*failed.*after.*seconds.*with.*([0-9]+).*issue ]]; then
        SUITE_NAME="${BASH_REMATCH[1]}"
        ISSUE_COUNT="${BASH_REMATCH[2]}"
        echo
        echo -e "${RED}${BOLD}✗ Suite Failed: ${SUITE_NAME}${NC}"
        echo -e "  ${YELLOW}Total issues in suite: ${ISSUE_COUNT}${NC}"
        continue
    fi

    if [[ "$line" =~ ^[[:space:]]*􀄵[[:space:]]*//.* ]] && [[ $IN_FAILURE_CONTEXT -eq 1 ]]; then
        echo -e "  ${MAGENTA}$line${NC}"
        continue
    fi

    if [[ "$line" =~ warning:.*is\ deprecated ]]; then
        continue
    fi

    if [[ "$line" =~ error:|ERROR:|fatal\ error: ]]; then
        echo -e "${RED}${BOLD}✗ COMPILATION ERROR${NC}"
        echo -e "${RED}$line${NC}"
        continue
    fi

    if [[ "$line" =~ ^(/[^:]+):([0-9]+):([0-9]+): ]]; then
        echo -e "${CYAN}$line${NC}"
        continue
    fi

    if [[ "$line" =~ "Building for debugging" ]] || [[ "$line" =~ "Build complete!" ]]; then
        echo -e "${BLUE}$line${NC}"
        continue
    fi

    if [[ "$line" =~ "Planning build" ]] || [[ "$line" =~ "Linking" ]]; then
        echo -e "${CYAN}$line${NC}"
        continue
    fi

    if [[ "$line" =~ "Fatal error:" ]]; then
        echo -e "${RED}${BOLD}✗ FATAL ERROR${NC}"
        echo -e "${RED}$line${NC}"
        continue
    fi

    if [[ "$line" =~ ^[[:space:]]*\[.*\].*(Write|Compiling|Emitting|Building) ]]; then
        continue
    fi

    if [[ -z "${line// }" ]]; then
        continue
    fi

done
