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

axc_path="./axc"
axc_dir=$(cd "$(dirname "$axc_path")" && pwd)

echo "Running 'saw test' in $axc_dir..."
if command -v saw >/dev/null 2>&1; then
    (cd "$axc_dir" && saw test)
    saw_exit=$?
    if [ $saw_exit -ne 0 ]; then
        echo "${RED}FAILED: saw test${RESET}"
        exit 1
    else
        echo "${GREEN}OK: saw test${RESET}"
    fi
else
    echo "${YELLOW}saw not found in PATH; skipping 'saw test'${RESET}"
fi

echo ""
echo "Testing self-compilation: building axc2 with tested axc..."
cd "$axc_dir" || exit 1
total=$((total + 1))
if [ -f "axc2" ]; then
    rm -f "axc2"
fi
echo "Running: ./axc axc -o axc2"
./axc axc -o axc2
scExit=$?

echo "Running: ./axc2 axc -o axc3"
./axc2 axc -o axc3 2>/dev/null
scExit=$?

cd - >/dev/null || exit 1

if [ $scExit -ne 0 ]; then
    echo "${RED}FAILED: self-compilation (axc -> axc2) - exit code $scExit${RESET}"
    failed=$((failed + 1))
    # track failed file marker for summary
    failed_files="$failed_files
self-compilation (exit $scExit)"
else
    if [ -f "$axc_dir/axc2" ]; then
        echo "${GREEN}OK: self-compilation (exit 0) produced $axc_dir/axc2${RESET}"
        passed=$((passed + 1))
    else
        echo "${YELLOW}WARNING: self-compilation returned exit 0 but $axc_dir/axc2 not found${RESET}"
        failed=$((failed + 1))
        failed_files="$failed_files
self-compilation (missing axc2)"
    fi
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

STD_DIR="./std"
if [ -d "$STD_DIR" ]; then
    echo ""
    echo "Compiling standard library files in $STD_DIR..."

    tmpfile=$(mktemp) || exit 1
    find "$STD_DIR" -type f -name "*.axe" | sort > "$tmpfile"

    while IFS= read -r file; do
        total=$((total + 1))
        echo "------------------------------"
        echo "Compiling $file"

        ./axc "$file"
        exit_code=$?

        if [ $exit_code -ne 0 ]; then
            echo "${RED}FAILED: $file${RESET}"
            failed=$((failed + 1))
            failed_files="$failed_files
$file"
        else
            echo "${GREEN}OK: $file${RESET}"
            passed=$((passed + 1))
        fi
    done < "$tmpfile"

    rm -f "$tmpfile"
else
    echo "${YELLOW}Std folder not found at $STD_DIR; skipping std compilation${RESET}"
fi

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
