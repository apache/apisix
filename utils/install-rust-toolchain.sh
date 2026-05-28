#!/usr/bin/env bash

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

function rustc_meets_minimum_version() {
    if ! command -v rustc >/dev/null 2>&1; then
        return 1
    fi

    local version major minor
    version=$(rustc --version | awk '{print $2}')
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+ ]]; then
        return 1
    fi

    major=${version%%.*}
    minor=${version#*.}
    minor=${minor%%.*}

    [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 77 ]; }
}

function run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

function install_rustup_toolchain() {
    local version target checksum tmp_dir tmp rustup_home cargo_home base_path
    version="1.28.2"
    rustup_home="${RUSTUP_HOME:-/usr/local/rustup}"
    cargo_home="${CARGO_HOME:-/usr/local/cargo}"
    base_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    case "$(uname -m)" in
        x86_64|amd64)
            target="x86_64-unknown-linux-gnu"
            checksum="20a06e644b0d9bd2fbdbfd52d42540bdde820ea7df86e92e533c073da0cdd43c"
            ;;
        aarch64|arm64)
            target="aarch64-unknown-linux-gnu"
            checksum="e3853c5a252fca15252d07cb23a1bdd9377a8c6f3efa01531109281ae47f841c"
            ;;
        *)
            echo "unsupported architecture for rustup-init: $(uname -m)"
            exit 1
            ;;
    esac

    tmp_dir=$(mktemp -d) || return 1
    (
        set -euo pipefail
        trap 'rm -rf "${tmp_dir}"' EXIT
        tmp="${tmp_dir}/rustup-init"
        curl -fsSLo "$tmp" "https://static.rust-lang.org/rustup/archive/${version}/${target}/rustup-init"
        echo "${checksum}  ${tmp}" | sha256sum -c -
        chmod +x "$tmp"
        run_as_root mkdir -p "$rustup_home" "$cargo_home"
        run_as_root env RUSTUP_HOME="$rustup_home" CARGO_HOME="$cargo_home" PATH="$base_path" \
            "$tmp" -y --profile minimal --default-toolchain stable --no-modify-path
        run_as_root env RUSTUP_HOME="$rustup_home" CARGO_HOME="$cargo_home" PATH="${cargo_home}/bin:${base_path}" \
            "${cargo_home}/bin/rustup" default stable
    ) || return 1
    export RUSTUP_HOME="$rustup_home"
    export CARGO_HOME="$cargo_home"
    export PATH="${cargo_home}/bin:${PATH}"
    if [[ -n "${GITHUB_ENV:-}" ]]; then
        {
            echo "RUSTUP_HOME=${rustup_home}"
            echo "CARGO_HOME=${cargo_home}"
        } >> "$GITHUB_ENV"
    fi
    if [[ -n "${GITHUB_PATH:-}" ]]; then
        echo "${cargo_home}/bin" >> "$GITHUB_PATH"
    fi
    run_as_root ln -sf "${cargo_home}/bin/cargo" /usr/local/bin/cargo
    run_as_root ln -sf "${cargo_home}/bin/rustc" /usr/local/bin/rustc
}

function install_rust_toolchain() {
    if rustc_meets_minimum_version; then
        return
    fi

    if command -v brew >/dev/null 2>&1; then
        brew install rust
        if rustc_meets_minimum_version; then
            return
        fi
        echo "installed rustc is older than 1.77"
        exit 1
    fi

    if command -v curl >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1; then
        install_rustup_toolchain
        if rustc_meets_minimum_version; then
            return
        fi
        echo "installed rustc is older than 1.77"
        exit 1
    fi

    if command -v apt-get >/dev/null 2>&1; then
        run_as_root apt-get install -y cargo
        if rustc_meets_minimum_version; then
            return
        fi
        echo "installed rustc is older than 1.77"
        exit 1
    fi

    if command -v yum >/dev/null 2>&1; then
        run_as_root yum install -y cargo rust
        if rustc_meets_minimum_version; then
            return
        fi
        echo "installed rustc is older than 1.77"
        exit 1
    fi

    if command -v pacman >/dev/null 2>&1; then
        run_as_root pacman -S rust --noconfirm
        if rustc_meets_minimum_version; then
            return
        fi
        echo "installed rustc is older than 1.77"
        exit 1
    fi

    echo "No supported Rust package manager found"
    exit 1
}
