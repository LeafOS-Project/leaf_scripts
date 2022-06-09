#!/bin/bash
#
# Copyright (C) 2017 The LineageOS Project
# Copyright (C) 2022 The LeafOS Project
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
    echo "Usage ${0} <merge|rebase> <oldaosptag> <newaosptag>"
}

# Verify argument count
if [ "$#" -ne 3 ]; then
    usage
    exit 1
fi

OPERATION="${1}"
OLDTAG="${2}"
NEWTAG="${3}"

if [ "${OPERATION}" != "merge" -a "${OPERATION}" != "rebase" ]; then
    usage
    exit 1
fi

# Check to make sure this is being run from the top level repo dir
if [ ! -e "build/envsetup.sh" ]; then
    echo "Must be run from the top level repo dir"
    exit 1
fi

# Source build environment (needed for aospremote)
. build/envsetup.sh

TOP="${ANDROID_BUILD_TOP}"
MERGEDREPOS="${TOP}/merged_repos.txt"
MANIFEST="${TOP}/.repo/manifests/snippets/leaf.xml"
BRANCH=$(git -C ${TOP}/.repo/manifests.git config --get branch.default.merge | sed 's#refs/heads/##g')
STAGINGBRANCH="staging/${BRANCH}_${OPERATION}-${NEWTAG}"

# Build list of LeafOS forked repos
PROJECTPATHS=$(grep "<remove-project" "${MANIFEST}" | sed -n 's/.*name="\([^"]\+\)".*/\1/p' | sed 's/^platform\///g')
# Moved to build/make in Oreo
PROJECTPATHS=$(echo $PROJECTPATHS | sed 's/ build / build\/make /g')

echo "#### Old tag = ${OLDTAG} Branch = ${BRANCH} Staging branch = ${STAGINGBRANCH} ####"

# Make sure manifest and forked repos are in a consistent state
echo "#### Verifying there are no uncommitted changes on LeafOS forked AOSP projects ####"
for PROJECTPATH in ${PROJECTPATHS} .repo/manifests; do
    # Skip fully removed projects
    [ ! -d "${TOP}/$PROJECTPATH" ] && continue;
    cd "${TOP}/${PROJECTPATH}"
    if [[ -n "$(git status --porcelain)" ]]; then
        echo "Path ${PROJECTPATH} has uncommitted changes. Please fix."
        exit 1
    fi
done
echo "#### Verification complete - no uncommitted changes found ####"

# Remove any existing list of merged repos file
rm -f "${MERGEDREPOS}"

# Iterate over each forked project
for PROJECTPATH in ${PROJECTPATHS}; do
    # Skip fully removed projects
    [ ! -d "${TOP}/$PROJECTPATH" ] && continue;
    cd "${TOP}/${PROJECTPATH}"
    aospremote | grep -v "Remote 'aosp' created"
    git fetch -q --tags aosp "${NEWTAG}"

    PROJECTOPERATION="${OPERATION}"

    # Check if we've actually changed anything before attempting to merge
    # If we haven't, just "git reset --hard" to the tag
    if [[ -z "$(git diff HEAD ${OLDTAG})" ]]; then
        git reset --hard "${NEWTAG}"
        echo -e "reset\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
        continue
    fi

    # Was there any change upstream? Skip if not.
    if [[ -z "$(git diff ${OLDTAG} ${NEWTAG})" ]]; then
        echo -e "nochange\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
        continue
    fi

    if [[ "${PROJECTOPERATION}" == "merge" ]]; then
        echo "#### Merging ${NEWTAG} into ${PROJECTPATH} ####"
        git merge --no-edit --log "${NEWTAG}"
    elif [[ "${PROJECTOPERATION}" == "rebase" ]]; then
        echo "#### Rebasing ${PROJECTPATH} onto ${NEWTAG} ####"
        git rebase --onto "${NEWTAG}" "${OLDTAG}"
    fi

    CONFLICT=""
    if [[ -n "$(git status --porcelain)" ]]; then
        CONFLICT="conflict-"
    fi
    echo -e "${CONFLICT}${PROJECTOPERATION}\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
done
