#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
claude plugin validate "$project_root/integrations/claude-quotabar" --strict
claude plugin marketplace add "$project_root/integrations" --scope user
claude plugin install quotabar-usage@quotabar-local --scope user
claude plugin update quotabar-usage@quotabar-local
print 'Open a local Claude Code session and run /reload-plugins, then /quotabar-sync.'
