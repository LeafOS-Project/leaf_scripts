#!/bin/bash

if [ -z "$GH_TOKEN" ]; then
	echo "GH_TOKEN is not set!"
	exit 1
fi

LEAF_VERSION=$(cat .repo/manifests/snippets/leaf.xml  | grep -i '<default revision' | cut -f2 -d '"' | cut -f3 -d '/')

for REPO in $(cat .repo/manifests/snippets/leaf.xml | grep -E 'LeafOS-Project|LeafOS-Blobs' | cut -f4 -d '"'); do
	curl -X PATCH \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: token $GH_TOKEN" \
        https://api.github.com/repos/$REPO \
	-d "{\"has_issues\":false,\"has_projects\":false,\"has_wiki\":false,\"default_branch\":\"$LEAF_VERSION\"}"
done
