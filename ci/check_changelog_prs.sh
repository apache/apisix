#!/bin/bash
#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

set -euo pipefail

old_tag=$1
new_tag=$2

# Function to compare versions
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n1)" != "$1"
}

# Check if versions are above 3.8.0
if ! version_gt "${old_tag#v}" "3.8.0"; then
    echo "Skipping check for versions below or equal to 3.8.0"
    exit 0
fi

# Configure PR types to ignore
IGNORE_TYPES=(
    "docs"
    "chore"
    "test"
    "ci"
)

# Configure PR numbers to ignore
IGNORE_PRS=(
    # 3.9.0
    10655 10857 10858 10887 10959 11029 11041 11053 11055 11061 10976 10984 11025
    # 3.10.0
    11105 11128 11169 11171 11280 11333 11081 11202 11469
    # 3.11.0
    11463 11570
    # 3.12.0
    11769 11816 11881 11905 11924 11926 11973 11991 11992 11829
)

# Build ignore pattern to match the following formats:
# - Direct keyword prefix (e.g., "docs:")
ignore_pattern=$(IFS="|"; echo "(${IGNORE_TYPES[*]}):|(${IGNORE_TYPES[*]})\([^)]*\):")

# Extract PRs between two versions from CHANGELOG.md
echo "Extracting PRs between $old_tag and $new_tag from CHANGELOG.md..."
changelog_prs=$(awk -v start="$new_tag" -v end="$old_tag" '
    BEGIN { flag = 0 }
    $0 ~ "^## " {
        if ($0 ~ start) { flag = 1; next }
        if (flag && $0 ~ end) { flag = 0 }
    }
    flag { print }
' CHANGELOG.md | grep -oE '#[0-9]+' | sort -n)

# Extract actual PRs from git log, filtering out configured types and specified PR numbers
echo -e "\nExtracting actual PRs from git log (excluding: ${IGNORE_TYPES[*]} and PRs: ${IGNORE_PRS[*]})..."
git_prs=$(git log "$old_tag".."$new_tag" --oneline | grep -vE "$ignore_pattern" | grep -oE '#[0-9]+' | sort -n)

# Filter out specified PR numbers
for pr in "${IGNORE_PRS[@]}"; do
    git_prs=$(echo "$git_prs" | grep -v "#$pr")
done

# Compare the two lists
echo -e "\nComparing PRs..."
missing_prs=$(comm -23 <(echo "$git_prs") <(echo "$changelog_prs"))

# Print comparison results
echo -e "\n=== PR Comparison Results ==="
echo -e "\nPRs in git log (sorted, excluding configured types):"
echo "$git_prs" | sed 's/^/  /'

echo -e "\nPRs in CHANGELOG.md (sorted):"
echo "$changelog_prs" | sed 's/^/  /'

if [ -z "$missing_prs" ]; then
    echo -e "\n✅ All PRs are included in CHANGELOG.md"
else
    echo -e "\n❌ Missing PRs in CHANGELOG.md (sorted):"
    echo "$missing_prs" | sed 's/^/  /'
    
    # Get detailed information for each missing PR
    echo -e "\nDetailed information about missing PRs:"
    for pr in $missing_prs; do
        pr_num=${pr#\#}  # Remove # symbol
        echo -e "\nPR $pr:"
        # Get PR commit information
        git log "$old_tag".."$new_tag" --oneline | grep "$pr" | while read -r line; do
            echo "  - $line"
        done
        # Try to get PR title (if possible)
        echo "  - PR URL: https://github.com/apache/apisix/pull/$pr_num"
    done
    exit 1
fi
