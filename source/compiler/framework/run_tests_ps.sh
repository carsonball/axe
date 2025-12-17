#!/bin/sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

cd .. || exit 1

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR" || exit 1

if [ ! -x "axc" ]; then
    echo "${RED}ERROR: axc not found in $PWD/axc${RESET}"
    exit 1
fi

total=0
passed=0
failed=0
failed_files=""
folders="../tests/self_tests ../tests/legacy_tests"

for folder in $folders; do
    if [ ! -d "$folder" ]; then
        echo "${YELLOW}Skipping missing folder: $folder${RESET}"
        continue
    fi

    echo ""
    echo "Running tests in $folder..."

    tmpfile=$(mktemp) || exit 1
    find "$folder" -type f -name "*.axe" > "$tmpfile"

    while IFS= read -r file; do
        total=$((total + 1))
        echo "------------------------------"
        echo "Running $file"

        ./axc "$file"
        exit_code=$?

        case "$file" in
            *_error.axe)
                if [ $exit_code -ne 0 ]; then
                    echo "${GREEN}OK (expected failure): $file${RESET}"
                    passed=$((passed + 1))
                else
                    echo "${RED}FAILED (expected error but succeeded): $file${RESET}"
                    failed=$((failed + 1))
                    failed_files="$failed_files
$file"
                fi
                ;;
            *)
                if [ $exit_code -ne 0 ]; then
                    echo "${RED}FAILED: $file${RESET}"
                    failed=$((failed + 1))
                    failed_files="$failed_files
$file"
                else
                    echo "${GREEN}OK: $file${RESET}"
                    passed=$((passed + 1))
                fi
                ;;
        esac
    done < "$tmpfile"

    rm -f "$tmpfile"
done

echo ""
echo "Summary: Total=$total Passed=$passed Failed=$failed"

if [ "$failed" -eq 0 ]; then
    echo "${GREEN}All tests passed.${RESET}"
else
    echo "${RED}Some tests failed.${RESET}"
    echo ""
    echo "Failed files:"
    echo "$failed_files" | sed '/^$/d' | sed 's/^/ - /'
fi

exit "$failed"
