#!/bin/bash

PATCHES_UPSTREAM=$(curl --silent https://api.github.com/repos/GrapheneOS/Vanadium/contents/patches?ref=main | jq)

for PATCH in patches/*.patch; do
    PATCH=$(basename $PATCH)
    NUM=$(echo $PATCH | cut -f1 -d '-')
    PATCHNAME=$(echo $PATCH | sed -e "s/^$NUM-//g")
    NEWNAME=$(echo "$PATCHES_UPSTREAM" | grep -e "\"patches/[0-9]*-$PATCHNAME\"")
    NEWNAME=$(echo "$NEWNAME" | cut -f4 -d '"')
    if [ -z "$NEWNAME" ]; then
        echo "Missing patch $PATCH"
        exit 1
    fi

    echo $NEWNAME
    mv patches/$PATCH patches/$(basename $NEWNAME)
    wget -O patches/$(basename $NEWNAME) https://raw.githubusercontent.com/GrapheneOS/Vanadium/main/$NEWNAME
done
