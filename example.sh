#!/bin/bash
set -euo pipefail

FAIL=0

check() {
    if ! "$@"; then
        echo "FAIL: $*"
        FAIL=1
    fi
}

webb start
webb open "https://example.com"
webb waitstable

check webb exists "h1"
check webb visible "h1"
check webb assert 'document.title' 'Example Domain'
check webb ax-find --role heading --name "Example Domain"

webb stop

if [ "$FAIL" -ne 0 ]; then
    echo "Some checks failed"
    exit 1
fi
echo "All checks passed"
