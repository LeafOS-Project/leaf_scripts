#!/usr/bin/env python3
#
# Copyright (C) 2023 LeafOS Project
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
import argparse
import os
import secrets
import subprocess
import sys
import requests
from xml.etree import ElementTree

PORT = "29418"
GERRIT = "review.leafos.org"

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-f", dest="project_file",
                        default=".repo/manifests/snippets/leaf.xml")
    parser.add_argument("-b", dest="branch")
    return parser.parse_args()

def check_gh_token():
    gh_token = os.environ.get("GH_TOKEN")
    if not gh_token:
        print("GH_TOKEN is not set!")
        sys.exit(1)
    return gh_token

def check_gh_user(token):
    user = requests.get(
        "https://api.github.com/user",
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
        },
    ).json()["login"]
    return user

def create_github_repo(org, repo, token):
    url = f"https://api.github.com/orgs/{org}/repos"
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"token {token}",
    }
    data = {
        "name": repo,
        "private": False,
        "has_issues": False,
        "has_projects": False,
        "has_wiki": False,
    }
    requests.post(url, headers=headers, json=data)

def set_github_repo_settings(project, branch, token):
    url = f"https://api.github.com/repos/{project}"
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"token {token}",
    }
    data = {
        "has_issues": False,
        "has_projects": False,
        "has_wiki": False,
        "default_branch": branch,
    }
    requests.patch(url, headers=headers, json=data)

def create_gerrit_project(project, branch, user):
    projects = subprocess.run(
        ["ssh", "-n", "-p", PORT, f"{user}@{GERRIT}", "gerrit", "ls-projects"],
        stdout=subprocess.PIPE,
        text=True,
    ).stdout.split("\n")
    if project not in projects:
        subprocess.run(
            ["ssh", "-n", "-p", PORT, f"{user}@{GERRIT}",
                "gerrit", "create-project", project, "-b", branch],
            check=True,
        )

def set_gerrit_project_head(project, branch, user):
    subprocess.run(
        ["ssh", "-n", "-p", PORT, f"{user}@{GERRIT}", "gerrit",
            "set-head", project, "--new-head", branch],
        check=False,
    )

def get_projects_from_manifests(project_file, branch):
    projects = []

    with open(project_file) as xml_file:
        root = ElementTree.parse(xml_file).getroot()

        for project in root.findall("project"):
            name = project.get("name")
            remote = project.get("remote") or root.find("default").get("remote")
            revision = branch or project.get("revision") or root.find("default").get("revision").split("/")[-1]
            projects.append({"name": name, "remote": remote, "revision": revision})

    return projects

def main():
    args = parse_args()

    gh_token = check_gh_token()
    gh_user = check_gh_user(gh_token)

    projects = get_projects_from_manifests(args.project_file, args.branch)
    for project in projects:
        name = project["name"]
        if project["remote"] != "aosp":
            print(name)
            org, repo = name.split("/")
            branch = project["revision"]
            create_github_repo(org, repo, gh_token)
            set_github_repo_settings(name, branch, gh_token)
            create_gerrit_project(name, branch, gh_user)
            set_gerrit_project_head(name, branch, gh_user)

if __name__ == "__main__":
    main()
