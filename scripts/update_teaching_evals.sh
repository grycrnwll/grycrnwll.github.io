#!/bin/bash

# Script to rebuild the teaching evaluations table from the GW evaluation report
#
# Download the multi-year report from the GW evaluation system, then run:
#   ./scripts/update_teaching_evals.sh                      # uses ~/Downloads/_All_Years.pdf
#   ./scripts/update_teaching_evals.sh path/to/report.pdf
#
# The script refuses to write anything unless every term mean it reconstructs
# matches the mean printed in the report, so a layout change fails loudly.

set -u

# Set the base directory to the repository root
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Define file paths
PYTHON_SCRIPT="$BASE_DIR/scripts/teaching_evals_to_html.py"
INCLUDE="$BASE_DIR/_includes/evals-toggle.html"
PDF="${1:-$HOME/Downloads/_All_Years.pdf}"

# Check if the Python script exists
if [ ! -f "$PYTHON_SCRIPT" ]; then
  echo "Error: Python script not found at $PYTHON_SCRIPT"
  exit 1
fi

# Check if the evaluation report exists
if [ ! -f "$PDF" ]; then
  echo "Error: evaluation report not found at $PDF"
  echo "Pass the path explicitly: $0 path/to/report.pdf"
  exit 1
fi

# Pick an available Python
PYTHON="python3"
command -v "$PYTHON" >/dev/null 2>&1 || PYTHON="python"
if ! command -v "$PYTHON" >/dev/null 2>&1; then
  echo "Error: no python3 or python on PATH"
  exit 1
fi

# Rebuild the include from the report
echo "Rebuilding evaluations table from $PDF..."
"$PYTHON" "$PYTHON_SCRIPT" --input "$PDF" --output "$INCLUDE" --report

# Check if the rebuild was successful
if [ $? -eq 0 ]; then
  echo
  echo "Done. Review the change before committing:"
  echo "    git diff -- $INCLUDE"
else
  echo "Error: failed to rebuild the evaluations table"
  exit 1
fi

exit 0
