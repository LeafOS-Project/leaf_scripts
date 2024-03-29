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
import json
import os
import requests
import subprocess
import sys
import yaml
from xml.etree import ElementTree

PORT = "29418"
GERRIT = "review.leafos.org"
leaf_devices = "leaf/devices/devices.yaml"
gerrit_structure = "leaf/gerrit-config/structure.yaml"

def parse_args():
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest='subcommand')
    subparsers.required = True

    # update
    parser_update = subparsers.add_parser('update')
    parser_update.add_argument("-b", "--branch")
    parser_update.add_argument("-d", "--device")
    parser_update.add_argument("-f", "--project_file",
                        default=".repo/manifests/snippets/leaf.xml")

    # update_groups
    parser_update_groups = subparsers.add_parser('update_groups')

    # fetch_structure_from_gerrit
    parser_fetch_structure = subparsers.add_parser('fetch_structure_from_gerrit')

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

def set_gerrit_project_parent(project, parent, user):
    subprocess.run(
        ["ssh", "-n", "-p", PORT, f"{user}@{GERRIT}", "gerrit",
            "set-project-parent", project, "--parent", parent],
        check=False,
    )

def get_projects_from_devices(device, branch):
    projects = []

    with open(leaf_devices) as f:
        root = yaml.safe_load(f)

    for item in root:
        if device in item["device"]:
            for repository in item["repositories"]:
                projects.append({"name": repository["name"], "revision": branch})

    return projects

def get_projects_from_manifests(project_file, branch):
    projects = []

    with open(project_file) as xml_file:
        root = ElementTree.parse(xml_file).getroot()

        for project in root.findall("project"):
            name = project.get("name")
            revision = branch or project.get("revision") or root.find("default").get("revision").split("/")[-1]
            projects.append({"name": name, "revision": revision})

    return projects

def get_projects_from_gerrit_structure():
    with open(gerrit_structure, "r") as f:
        return yaml.safe_load(f)

def get_projects_from_gerrit(auth=None):
    url = f"https://{GERRIT}/a/projects/?t" if auth else f"https://{GERRIT}/projects/?t"
    resp = requests.get(url, auth=auth)
    if resp.status_code != 200:
        raise Exception(f"Error communicating with gerrit: {resp.text}")
    projects = json.loads(resp.text[5:])
    nodes = {}

    for name, project in projects.items():
        nodes[name] = []

    for name, project in projects.items():
        parent = project.get("parent")
        if parent:
            nodes[parent].append(name)
    for project in nodes.keys():
        nodes[project] = sorted(nodes[project])
    return nodes

def main():
    args = parse_args()

    gh_token = check_gh_token()
    gh_user = check_gh_user(gh_token)

    if args.subcommand == 'update':
        if (args.device):
            projects = get_projects_from_devices(args.device, args.branch)
        else:
            projects = get_projects_from_manifests(args.project_file, args.branch)
        for project in projects:
            name = project["name"]
            if ("LeafOS-Project" in name) or ("LeafOS-Blobs" in name) or ("LeafOS-Devices" in name):
                print(name)
                org, repo = name.split("/")
                branch = project["revision"]
                create_github_repo(org, repo, gh_token)
                set_github_repo_settings(name, branch, gh_token)
                create_gerrit_project(name, branch, gh_user)
                set_gerrit_project_head(name, branch, gh_user)
    elif args.subcommand == 'update_groups':
        projects = get_projects_from_gerrit_structure()
        live_projects = get_projects_from_gerrit()
        changes = {}

        for parent, children in projects.items():
            if parent in live_projects:
                if (not projects[parent] or set(live_projects[parent]) == set(projects[parent])):
                    continue
                else:
                    changes[parent] = list(set(projects[parent]) - set(live_projects[parent]))
                    if not changes[parent]:
                        del changes[parent]
            else:
                changes[parent] = children

        if changes:
            for parent, children in changes.items():
                for child in children:
                   print(f"Update parent of {child} to {parent}")
                   set_gerrit_project_parent(child, parent, gh_user)
    elif args.subcommand == 'fetch_structure_from_gerrit':
        projects = get_projects_from_gerrit()

        for node in sorted(projects.keys()):
            children = sorted(projects[node])
            if children:
                print(f"{node}:")
                for child in projects[node]:
                    print(f"  - {child}")

if __name__ == "__main__":
    main()
