#!/bin/bash

PATCHES_UPSTREAM=$(curl --silent https://github.com/GrapheneOS/Vanadium/tree/main/patches | jq)

for PATCH in patches/*.patch; do
    PATCH=$(basename $PATCH)
    NUM=$(echo $PATCH | cut -f1 -d '-')
    PATCHNAME=$(echo $PATCH | sed -e "s/^$NUM-//g")
    NEWNAME=$(echo "$PATCHES_UPSTREAM" | grep -e "\"[0-9]*-$PATCHNAME\"")
    NEWNAME=$(echo "$NEWNAME" | cut -f4 -d '"')
    if [ -z "$NEWNAME" ]; then
        echo "Missing patch $PATCH"
        exit 1
    fi

    echo $NEWNAME
    mv patches/$PATCH patches/$NEWNAME
    wget -O patches/$NEWNAME https://raw.githubusercontent.com/GrapheneOS/Vanadium/main/patches/$NEWNAME
done
