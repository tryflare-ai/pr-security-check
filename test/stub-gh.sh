#!/bin/bash
# Stand-in for the GitHub CLI in the `uses: ./` smoke job.
echo "gh $*" >> "$RUNNER_TEMP/gh.log"
case "$*" in
  "issue create"*) echo "https://github.com/o/r/issues/1" ;;
esac
