#!/bin/bash

# PostRecoveryX Automated Testing & Validation Script
# This script ensures the app builds successfully and all tests pass

set -e  # Exit on error

echo "=================================================="
echo "PostRecoveryX Automated Testing & Validation"
echo "=================================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    if [ "$1" = "success" ]; then
        echo -e "${GREEN}✓ $2${NC}"
    elif [ "$1" = "error" ]; then
        echo -e "${RED}✗ $2${NC}"
    elif [ "$1" = "warning" ]; then
        echo -e "${YELLOW}⚠ $2${NC}"
    else
        echo "$2"
    fi
}

# Change to project directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# 1. Clean build folder
echo "1. Cleaning build folder..."
if xcodebuild clean -project PostRecoveryX.xcodeproj -scheme PostRecoveryX -quiet; then
    print_status "success" "Build folder cleaned"
else
    print_status "error" "Failed to clean build folder"
    exit 1
fi
echo ""

# 2. Build the project
echo "2. Building PostRecoveryX..."
if xcodebuild -project PostRecoveryX.xcodeproj -scheme PostRecoveryX build -quiet; then
    print_status "success" "Build succeeded"
else
    print_status "error" "Build failed"
    exit 1
fi
echo ""

# 3. Run unit tests
echo "3. Running unit tests..."
if xcodebuild test -project PostRecoveryX.xcodeproj -scheme PostRecoveryX -quiet 2>&1 | grep -E "(Test Suite|passed|failed)" || true; then
    if xcodebuild test -project PostRecoveryX.xcodeproj -scheme PostRecoveryX -quiet 2>&1 | grep -q "TEST FAILED"; then
        print_status "error" "Some tests failed"
        exit 1
    else
        print_status "success" "All tests passed"
    fi
else
    print_status "warning" "No test results found"
fi
echo ""

# 4. Check for SwiftLint issues (if installed)
echo "4. Checking code quality..."
if command -v swiftlint &> /dev/null; then
    LINT_OUTPUT=$(swiftlint lint --quiet 2>&1 || true)
    LINT_COUNT=$(echo "$LINT_OUTPUT" | grep -E "(warning|error)" | wc -l | tr -d ' ')
    
    if [ "$LINT_COUNT" -eq 0 ]; then
        print_status "success" "No linting issues found"
    else
        print_status "warning" "$LINT_COUNT linting issues found"
        echo "$LINT_OUTPUT" | grep -E "(warning|error)" | head -10
        echo "..."
    fi
else
    print_status "warning" "SwiftLint not installed - skipping code quality check"
fi
echo ""

# 5. Performance validation
echo "5. Checking for performance issues..."

# Check for .save() calls in loops
SAVE_IN_LOOPS=$(grep -r "\.save()" PostRecoveryX --include="*.swift" | grep -E "(for|while)" | wc -l | tr -d ' ')
if [ "$SAVE_IN_LOOPS" -gt 0 ]; then
    print_status "warning" "Found $SAVE_IN_LOOPS potential .save() calls in loops"
else
    print_status "success" "No .save() calls found in loops"
fi

# Check for unbounded @Query
UNBOUNDED_QUERIES=$(grep -r "@Query.*\[.*\]" PostRecoveryX --include="*.swift" | grep -v "fetchLimit\|offset\|predicate" | wc -l | tr -d ' ')
if [ "$UNBOUNDED_QUERIES" -gt 0 ]; then
    print_status "warning" "Found $UNBOUNDED_QUERIES potentially unbounded @Query operations"
else
    print_status "success" "No unbounded @Query operations found"
fi

# Check for lockFocus usage
LOCK_FOCUS=$(grep -r "lockFocus()" PostRecoveryX --include="*.swift" | wc -l | tr -d ' ')
if [ "$LOCK_FOCUS" -gt 0 ]; then
    print_status "warning" "Found $LOCK_FOCUS deprecated lockFocus() calls"
else
    print_status "success" "No deprecated lockFocus() calls found"
fi
echo ""

# 6. Memory usage check
echo "6. Checking memory usage patterns..."

# Check for large array operations without batching
LARGE_ARRAYS=$(grep -r "\.map\|\.filter\|\.reduce" PostRecoveryX --include="*.swift" | grep -v "chunked\|batch\|slice" | wc -l | tr -d ' ')
if [ "$LARGE_ARRAYS" -gt 50 ]; then
    print_status "warning" "Found many array operations that might need batching"
else
    print_status "success" "Array operations seem reasonable"
fi
echo ""

# 7. Build for release
echo "7. Building Release configuration..."
if xcodebuild -project PostRecoveryX.xcodeproj -scheme PostRecoveryX -configuration Release build -quiet; then
    print_status "success" "Release build succeeded"
else
    print_status "error" "Release build failed"
    exit 1
fi
echo ""

# Summary
echo "=================================================="
echo "Testing & Validation Complete!"
echo "=================================================="
print_status "success" "PostRecoveryX is ready for use"
echo ""
echo "Performance tips:"
echo "- Always test with large datasets (100,000+ files)"
echo "- Monitor Activity Monitor during scans"
echo "- Check Console.app for any runtime warnings"
echo ""