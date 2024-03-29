#!/bin/bash
#
# Copyright (C) 2023 The LeafOS Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

usage() {
    echo "Usage ${0} -n <new-tag>"
}

# Verify argument count
if [ "${#}" -lt 2 ]; then
    usage
    exit 1
fi

while [ "${#}" -gt 0 ]; do
    case "${1}" in
        -n | --new-tag)
           NEWTAG="${2}"; shift
           ;;
        *)
           usage
           exit 1
           ;;
    esac
    shift
done

# Check to make sure this is being run from the top level repo dir
if [ ! -e "build/envsetup.sh" ]; then
    echo "Must be run from the top level repo dir"
    exit 1
fi

# Source build environment (needed for gettop)
. build/envsetup.sh

TOP="$(gettop)"
MERGEDREPOS="${TOP}/merged_repos.txt"
MANIFEST="${TOP}/.repo/manifests/snippets/leaf.xml"
BRANCH=$(git -C ${TOP}/.repo/manifests.git config --get branch.default.merge | sed 's#refs/heads/##g')
TOPIC="${NEWTAG}"

for PROJECTPATH in $(cat "${MERGEDREPOS}" | grep 'merge' | cut -f3); do
    cd "${TOP}/${PROJECTPATH}"

    echo "#### Pushing ${PROJECTPATH} merge to review ####"
    MERGE="$(git log --pretty=%H --merges -n 1)"
    FIRST_SHA="$(git show -s --pretty=%P ${MERGE} | cut -d ' ' -f 1)"
    SECOND_SHA="$(git show -s --pretty=%P ${MERGE} | cut -d ' ' -f 2)"
    git push leaf HEAD:refs/for/"${BRANCH}"%base="${FIRST_SHA}",base="${SECOND_SHA}",topic="${TOPIC}"
done
