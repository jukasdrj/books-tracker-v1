#!/bin/bash
# GitHub Project configuration for automation scripts
# NOTE: Update PROJECT_NUMBER after creating the GitHub Project Board
export PROJECT_NUMBER=2  # BooksTracker Development project
export REPO_OWNER=$(gh repo view --json owner -q .owner.login)
export REPO_NAME=$(gh repo view --json name -q .name)
