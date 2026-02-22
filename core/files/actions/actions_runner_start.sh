#!/bin/bash
set -e
cd /home/docker/actions-runner
./config.sh --url "$REPO_URL" --unattended --token "$RUNNER_TOKEN"
./run.sh