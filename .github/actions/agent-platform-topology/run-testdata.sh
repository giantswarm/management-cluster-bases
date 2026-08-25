#!/usr/bin/env bash
# Runs check-agent-platform-topology.sh in strict mode against every fixture in
# testdata/ and compares the exit code with testdata/expected.txt.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
while read -r fixture expected; do
  actual=0
  AGENT_PLATFORM_TOPOLOGY_STRICT=true "${here}/check-agent-platform-topology.sh" "${here}/testdata/${fixture}" >/dev/null 2>&1 || actual=$?
  if [[ "${actual}" == "${expected}" ]]; then
    echo "ok    ${fixture} (exit ${actual})"
  else
    echo "FAIL  ${fixture}: expected exit ${expected}, got ${actual}"
    rc=1
  fi
done < "${here}/testdata/expected.txt"
exit ${rc}
