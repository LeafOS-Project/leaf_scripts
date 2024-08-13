#!/bin/bash
#
# Copyright (C) 2022-2024 The LeafOS Project
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
    echo "Usage ${0} <branch>"
}

# Verify argument count
if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

BRANCH="${1}"

# Check to make sure this is being run from the top level repo dir
if [ ! -e "build/envsetup.sh" ]; then
    echo "Must be run from the top level repo dir"
    exit 1
fi

# Source build environment (needed for gettop)
. build/envsetup.sh

TOP="$(gettop)"
MERGEDREPOS="${TOP}/merged_repos_lineage_translations.txt"
MANIFEST="${TOP}/.repo/manifests/snippets/leaf.xml"
LEAF_BRANCH=$(git -C ${TOP}/.repo/manifests.git config --get branch.default.merge | sed 's#refs/heads/##g')

# Build list of LeafOS forked repos
PROJECTPATHS=$(repo forall -g default,-lineage -c '[ ! -z "$(find -name cm_strings.xml -or -name cm_plurals.xml)" ] && echo "$REPO_PATH "')

echo "#### LineageOS branch = ${BRANCH} Branch = ${LEAF_BRANCH} ####"

# Make sure manifest and forked repos are in a consistent state
echo "#### Verifying there are no uncommitted changes on projects containing LineageOS strings ####"
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

# Iterate over each project
for PROJECTPATH in ${PROJECTPATHS}; do
    # Skip fully removed projects
    [ ! -d "${TOP}/$PROJECTPATH" ] && continue;
    cd "${TOP}/${PROJECTPATH}"
    echo "### Fetching LineageOS strings from ${BRANCH} into ${PROJECTPATH} ###"

    EXTRAREFS=""
    EXTRAPATHREPLACE=""
    # Upstream has some Settings strings in a dedicated repo
    if [ "$PROJECTPATH" = "packages/apps/Settings" ]; then
        git fetch https://github.com/LineageOS/android_packages_apps_LineageParts "${BRANCH}"
        EXTRAREFS=$(git rev-parse FETCH_HEAD)
    fi
    # Upstream has some fwb strings in a dedicated repo
    if [ "$PROJECTPATH" = "frameworks/base" ]; then
        git fetch https://github.com/LineageOS/android_lineage-sdk "${BRANCH}"
        EXTRAREFS=$(git rev-parse FETCH_HEAD)
        EXTRAPATHREPLACE="^core|lineage"
        EXTRAPATHREPLACE_REV="^lineage|core"
    fi

    git fetch https://github.com/LineageOS/android_$(echo $PROJECTPATH | sed 's|/|_|g') "${BRANCH}"

    # Delete old translations
    find -iregex '.*/values-.*/cm_\(strings\|plurals\).xml' -delete
    for CM_STRINGS in $(find -iregex '.*/values/cm_\(strings\|plurals\).xml'); do
        STRINGS_TO_FIND=$(grep -Po '<(string|plurals) name="\K[^"]*' "$CM_STRINGS")
        PATTERN="$(dirname $CM_STRINGS | sed 's|^\./||g')-[^/]*/$(basename $CM_STRINGS)"

        for REF in "FETCH_HEAD" $EXTRAREFS; do
            LOCAL_PATTERN="$PATTERN"
            if [ "$REF" != "FETCH_HEAD" ]; then
                if [ ! -z "$EXTRAPATHREPLACE" ]; then
                    LOCAL_PATTERN="$(echo $LOCAL_PATTERN | sed -e "s|$EXTRAPATHREPLACE|g")"
                fi

                if [ "$(basename $CM_STRINGS)" = "cm_plurals.xml" ]; then
                    LOCAL_PATTERN="$(echo $LOCAL_PATTERN | sed -e 's/cm_plurals.xml$/plurals.xml/g')"
                else
                    LOCAL_PATTERN="$(echo $LOCAL_PATTERN | sed -e 's/cm_strings.xml$/strings.xml/g')"
                fi
            fi

            for TRANSLATION in $(git ls-tree -r --name-only "$REF" | grep -P "$LOCAL_PATTERN"); do
                FILENAME="$TRANSLATION"
                if [ "$REF" != "FETCH_HEAD" ]; then
                    if [ ! -z "$EXTRAPATHREPLACE_REV" ]; then
                        FILENAME="$(echo $FILENAME | sed -e "s|$EXTRAPATHREPLACE_REV|g")"
                    fi

                    if [ "$(basename $TRANSLATION)" = "plurals.xml" ]; then
                        FILENAME="$(echo $FILENAME | sed -e 's/plurals.xml$/cm_plurals.xml/g')"
                    else
                        FILENAME="$(echo $FILENAME | sed -e 's/strings.xml$/cm_strings.xml/g')"
                    fi
                fi

                mkdir -p $(dirname "$FILENAME")
                if [ ! -f "$FILENAME" ]; then
                    echo '<?xml version="1.0" encoding="utf-8"?>' > "$FILENAME"
                    GIT_PAGER="cat" git show "$REF":"$TRANSLATION" | grep -Pzo '<!--(\n( )*Copyright|\n/\*\*\n( )*\* Copyright)[\s\S]*?-->' | sed 's/\x0$/\n/g' >> "$FILENAME"
                    echo '<resources xmlns:xliff="urn:oasis:names:tc:xliff:document:1.2">' >> "$FILENAME"
                fi

                for STRING in $STRINGS_TO_FIND; do
                    LINE=$(GIT_PAGER="cat" git show "$REF":"$TRANSLATION" | grep -Pzo "    <(string|plurals) name=\"$STRING\">[\s\S]*?</(string|plurals)>" | sed 's/\x0$/\n/g')
                    EXISTING_LINE=$(grep -Pzo "    <(string|plurals) name=\"$STRING\">[\s\S]*?</(string|plurals)>" "$FILENAME")

                    if [ ! -z "$EXISTING_LINE" ]; then
                        echo "WARNING: Skipping duplicate string $STRING"
                    fi

                    if [ ! -z "$LINE" ]; then
                        echo "$LINE" >> "$FILENAME"
                    fi
                done
            done
        done
    done
    # Insert closing resources tag into all new files
    for CM_STRINGS in $(find -iregex '.*/values-.*/cm_\(strings\|plurals\).xml'); do
        echo '</resources>' >> $CM_STRINGS
    done

    if [[ -n "$(git status --porcelain)" ]]; then
        git add .
        git commit -m "Import cm_strings translations from lineage"
        echo -e "import\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
    else
        echo -e "nochange\t\t${PROJECTPATH}" | tee -a "${MERGEDREPOS}"
    fi
done
