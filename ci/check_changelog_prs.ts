/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements.  See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0
 * (the "License"); you may not use this file except in compliance with
 * the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { execSync } from 'child_process';
import { readFileSync } from 'fs';
import { join } from 'path';

// Types
interface Version {
    tag: string;
    ref: string;
}

interface PR {
    number: number;
    title: string;
    commit: string;
}

// Configuration
const IGNORE_TYPES = [
    'docs',
    'chore',
    'test',
    'ci'
];

const IGNORE_PRS = [
    // 3.9.0
    10655, 10857, 10858, 10887, 10959, 11029, 11041, 11053, 11055, 11061, 10976, 10984, 11025,
    // 3.10.0
    11105, 11128, 11169, 11171, 11280, 11333, 11081, 11202, 11469,
    // 3.11.0
    11463, 11570,
    // 3.12.0
    11769, 11816, 11881, 11905, 11924, 11926, 11973, 11991, 11992, 11829
];


function getGitRef(version: string): string {
    try {
        execSync(`git rev-parse ${version}`, { stdio: 'ignore' });
        return version;
    } catch {
        return 'HEAD';
    }
}

function extractVersionsFromChangelog(): Version[] {
    const changelogPath = join(process.cwd(), '..', 'CHANGELOG.md');
    const content = readFileSync(changelogPath, 'utf-8');
    const versionRegex = /^## ([0-9]+\.[0-9]+\.[0-9]+)/gm;
    const versions: Version[] = [];
    let match;

    while ((match = versionRegex.exec(content)) !== null) {
        const tag = match[1];
        versions.push({
            tag,
            ref: getGitRef(tag)
        });
    }

    return versions;
}

function extractPRsFromChangelog(startTag: string, endTag: string): number[] {
    const changelogPath = join(process.cwd(), '..', 'CHANGELOG.md');
    const content = readFileSync(changelogPath, 'utf-8');
    const lines = content.split('\n');
    let inRange = false;
    const prs: number[] = [];

    for (const line of lines) {
        if (line.startsWith(`## ${startTag}`)) {
            inRange = true;
            continue;
        }
        if (inRange && line.startsWith(`## ${endTag}`)) {
            break;
        }
        if (inRange) {
            const match = line.match(/#(\d+)/);
            if (match) {
                prs.push(parseInt(match[1], 10));
            }
        }
    }

    return prs.sort((a, b) => a - b);
}


function shouldIgnoreCommitMessage(message: string): boolean {
    // Extract the commit message part (remove the commit hash)
    const messagePart = message.split(' ').slice(1).join(' ');

    // Check if the message starts with any of the ignored types
    for (const type of IGNORE_TYPES) {
        // Check simple format: "type: message"
        if (messagePart.startsWith(`${type}:`)) {
            return true;
        }
        // Check format with scope: "type(scope): message"
        if (messagePart.startsWith(`${type}(`)) {
            const closingBracketIndex = messagePart.indexOf('):');
            if (closingBracketIndex !== -1) {
                return true;
            }
        }
    }
    return false;
}

function extractPRsFromGitLog(oldRef: string, newRef: string): PR[] {
    const log = execSync(`git log ${oldRef}..${newRef} --oneline`, { encoding: 'utf-8' });
    const prs: PR[] = [];

    for (const line of log.split('\n')) {
        if (!line.trim()) continue;

        // Check if this commit should be ignored
        if (shouldIgnoreCommitMessage(line)) continue;

        // Find PR number
        const prMatch = line.match(/#(\d+)/);
        if (prMatch) {
            const prNumber = parseInt(prMatch[1], 10);
            if (!IGNORE_PRS.includes(prNumber)) {
                prs.push({
                    number: prNumber,
                    title: line,
                    commit: line.split(' ')[0]
                });
            }
        }
    }

    return prs.sort((a, b) => a.number - b.number);
}

function findMissingPRs(changelogPRs: number[], gitPRs: PR[]): PR[] {
    const changelogPRSet = new Set(changelogPRs);
    return gitPRs.filter(pr => !changelogPRSet.has(pr.number));
}

function versionGreaterThan(v1: string, v2: string): boolean {
    // Remove 'v' prefix if present
    const cleanV1 = v1.replace(/^v/, '');
    const cleanV2 = v2.replace(/^v/, '');

    // Split version strings into arrays of numbers
    const v1Parts = cleanV1.split('.').map(Number);
    const v2Parts = cleanV2.split('.').map(Number);

    // Compare each part
    for (let i = 0; i < Math.max(v1Parts.length, v2Parts.length); i++) {
        const v1Part = v1Parts[i] || 0;
        const v2Part = v2Parts[i] || 0;

        if (v1Part > v2Part) return true;
        if (v1Part < v2Part) return false;
    }

    // If all parts are equal, return false
    return false;
}

// Main function
async function main() {
    try {
        const versions = extractVersionsFromChangelog();
        let hasErrors = false;

        for (let i = 0; i < versions.length - 1; i++) {
            const newVersion = versions[i];
            const oldVersion = versions[i + 1];

            // Skip if new version is less than or equal to 3.8.0
            if (!versionGreaterThan(newVersion.tag, '3.8.0')) {
                continue;
            }

            console.log(`\n=== Checking changes between ${newVersion.tag} (${newVersion.ref}) and ${oldVersion.tag} (${oldVersion.ref}) ===`);

            const changelogPRs = extractPRsFromChangelog(newVersion.tag, oldVersion.tag);
            const gitPRs = extractPRsFromGitLog(oldVersion.ref, newVersion.ref);
            const missingPRs = findMissingPRs(changelogPRs, gitPRs);

            console.log(`\n=== PR Comparison Results for ${newVersion.tag} ===`);

            if (missingPRs.length === 0) {
                console.log(`\n✅ All PRs are included in CHANGELOG.md for version ${newVersion.tag}`);
            } else {
                console.log(`\n❌ [ERROR] Missing PRs in CHANGELOG.md for version ${newVersion.tag} (sorted):`);
                missingPRs.forEach(pr => {
                    console.log(`  #${pr.number}`);
                });

                console.log(`\nDetailed information about missing PRs for version ${newVersion.tag}:`);
                missingPRs.forEach(pr => {
                    console.log(`\nPR #${pr.number}:`);
                    console.log(`  - ${pr.title}`);
                    console.log(`  - PR URL: https://github.com/apache/apisix/pull/${pr.number}`);
                });

                console.log('Note: If you confirm that a PR should not appear in the changelog, please add its number to the IGNORE_PRS array in this script.');
                hasErrors = true;
            }
        }

        if (hasErrors) {
            process.exit(1);
        }
    } catch (error) {
        console.error('Error:', error);
        process.exit(1);
    }
}

main();
