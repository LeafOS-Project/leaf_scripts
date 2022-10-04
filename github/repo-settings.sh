#!/bin/bash

if [ -z "$GH_TOKEN" ]; then
	echo "GH_TOKEN is not set!"
	exit 1
fi

LEAF_VERSION=$(cat .repo/manifests/snippets/leaf.xml  | grep -i '<default revision' | cut -f2 -d '"' | cut -f3 -d '/')

for REPO in $(cat .repo/manifests/snippets/leaf.xml | grep -E 'LeafOS-Project|LeafOS-Blobs|LeafOS-Devices' | cut -f4 -d '"'); do
	echo $REPO
	curl -X POST \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: token $GH_TOKEN" \
	https://api.github.com/orgs/$(echo $REPO | cut -f1 -d '/')/repos \
	-d "{\"name\":\"$(echo $REPO | cut -f2 -d '/')\",\"private\":false,\"has_issues\":false,\"has_projects\":false,\"has_wiki\":false}" \
	--silent > /dev/null
	curl -X PATCH \
	-H "Accept: application/vnd.github+json" \
	-H "Authorization: token $GH_TOKEN" \
        https://api.github.com/repos/$REPO \
	-d "{\"has_issues\":false,\"has_projects\":false,\"has_wiki\":false,\"default_branch\":\"$LEAF_VERSION\"}" \
	--silent > /dev/null
done
