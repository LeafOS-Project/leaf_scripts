#!/bin/bash

if [ -z "$GH_TOKEN" ]; then
	echo "GH_TOKEN is not set!"
	exit 1
fi

PORT="29418"
GERRIT="review.leafos.org"
GERRIT_PROJECTS=$(ssh -p "$PORT" "$GERRIT" gerrit ls-projects)

LEAF_VERSION=$(grep -i '<default revision' .repo/manifests/snippets/leaf.xml | cut -f2 -d '"' | cut -f3 -d '/')

grep -E 'LeafOS-Project|LeafOS-Blobs|LeafOS-Devices' .repo/manifests/snippets/leaf.xml | while IFS= read -r project; do
	PROJECT=$(cut -f4 -d '"' <<<"$project")
	ORG=$(echo "$PROJECT" | cut -f1 -d '/')
	REPO=$(echo "$PROJECT" | cut -f2 -d '/')

	echo "$PROJECT"

	# Github
	curl -s -X POST \
		-H "Accept: application/vnd.github+json" \
		-H "Authorization: token $GH_TOKEN" \
		"https://api.github.com/orgs/$ORG/repos" \
		-d "{
		\"name\":\"$REPO\",
		\"private\":false,
		\"has_issues\":false,
		\"has_projects\":false,
		\"has_wiki\":false
		}" >/dev/null

	curl -s -X PATCH \
		-H "Accept: application/vnd.github+json" \
		-H "Authorization: token $GH_TOKEN" \
		"https://api.github.com/repos/$PROJECT" \
		-d "{
		\"has_issues\":false,
		\"has_projects\":false,
		\"has_wiki\":false,
		\"default_branch\":\"$LEAF_VERSION\"
		}" >/dev/null

	# Gerrit
	if ! [[ $GERRIT_PROJECTS =~ $PROJECT ]]; then
		ssh -p "$PORT" "$GERRIT" gerrit create-project "$PROJECT" -b "$LEAF_VERSION"
	fi

	if ! grep -q revision <<<"$project"; then
		ssh -p "$PORT" "$GERRIT" gerrit set-head "$PROJECT" --new-head "$LEAF_VERSION"
	fi
done
