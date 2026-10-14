#!/usr/bin/env python3
"""
Generate the aggregate course-evaluation table from a GW evaluation report PDF.

Reads the multi-term evaluation export (e.g. _All_Years.pdf) and writes the
Jekyll include that renders the collapsible "Evaluations" table on /teaching/.

Statistics are pooled at the STUDENT level. The script reconstructs each term's
response distribution from the per-item counts printed in the report, then sums
those counts across terms. It deliberately does not average the per-term means,
which would weight a 4-respondent term the same as a 17-respondent one.

Every reconstructed term mean is checked against the mean GW printed for that
item. A mismatch is a hard error: if GW changes the report layout, this script
fails loudly instead of quietly emitting wrong numbers.

Requires PyMuPDF:  python3 -m pip install pymupdf

Usage:
    python3 scripts/teaching_evals_to_html.py --input ~/Downloads/_All_Years.pdf
    python3 scripts/teaching_evals_to_html.py --input report.pdf --report --dry-run
"""

import argparse
import difflib
import io
import json
import math
import os
import re
import sys

# Rated items to show, in table order: (key, table label, question-text pattern).
# Add or remove a row here; the label is what appears in the rendered table.
ITEMS = [
    ("overall",    "Overall instructor rating",  r"Overall instructor rating"),
    ("knowledge",  "Instructor knowledge",       r"Instructor knowledgeable about subject"),
    ("enthusiasm", "Instructor enthusiasm",      r"Instructor enthusiastic about subject"),
    ("challenge",  "Intellectual challenge",     r"Level of intellectual challenge"),
    ("learned",    "How much learned in course", r"How much learned in course"),
]

COURSE_RE = re.compile(r"^(Spring|Summer|Fall|Winter) (\d{4}), ECON 6376")
POSSIBLE_RE = re.compile(r"There were: (\d+) possible respondents")
# N followed by the item's own mean, the department mean and the college mean.
DATA_RE = re.compile(r"(?:^|\s)(\d{1,3})\s+(\d\.\d)\s+(\d\.\d)\s+(\d\.\d)(?:\s|$)")
PCT_RE = re.compile(r"^\d+%$")
COUNT_RE = re.compile(r"^\((\d+)\)$")

SEASONS = {"Spring": 0, "Summer": 1, "Fall": 2, "Winter": 3}
ROW_TOL = 1.5    # points; tokens within this vertical distance form one text row
CELL_TOL = 8.0   # points; how far a wrapped table cell can sit from its data row


def half_up(x, digits=0):
    """Round half away from zero, as the GW report does (Python rounds half to even)."""
    factor = 10 ** digits
    return math.floor(x * factor + 0.5) / factor


def text_rows(pdf_path):
    """Return [(page_index, y, [(x, token), ...]), ...] for every text row in the PDF."""
    try:
        import fitz  # PyMuPDF
    except ImportError:
        sys.exit("Error: PyMuPDF is required.  Install it with:\n"
                 "    python3 -m pip install pymupdf")

    rows = []
    with fitz.open(pdf_path) as doc:
        for page_index, page in enumerate(doc):
            words = page.get_text("words")
            words.sort(key=lambda w: (round(w[1], 1), w[0]))
            row_y, row = None, None
            for x0, y0, _x1, _y1, token, *_rest in words:
                y = round(y0, 1)
                if row is None or abs(y - row_y) > ROW_TOL:
                    row = []
                    rows.append((page_index, y, row))
                    row_y = y
                row.append((x0, token))
    return rows


def row_text(row):
    return " ".join(token for _x, token in row[2])


def parse_terms(rows):
    """Split the report into terms and pull every numeric item out of each one."""
    terms = []
    for index, row in enumerate(rows):
        match = COURSE_RE.match(row_text(row))
        if match:
            terms.append({"term": "%s %s" % (match.group(1), match.group(2)),
                          "season": SEASONS[match.group(1)],
                          "year": int(match.group(2)),
                          "start": index, "possible": None, "items": []})
    if not terms:
        sys.exit("Error: no 'ECON 6376' term headings found. Is this the right PDF?")

    for position, term in enumerate(terms):
        term["end"] = terms[position + 1]["start"] if position + 1 < len(terms) else len(rows)

    for term in terms:
        segment = rows[term["start"]:term["end"]]
        for row in segment:
            match = POSSIBLE_RE.search(row_text(row))
            if match:
                term["possible"] = int(match.group(1))
                break
        if term["possible"] is None:
            sys.exit("Error: no respondent total found for %s." % term["term"])

        for row in segment:
            match = DATA_RE.search(row_text(row))
            if match:
                term["items"].append(read_item(rows, row, match))

    return sorted(terms, key=lambda t: (t["year"], t["season"]))


def read_item(rows, row, match):
    """Read one rated item: its question text, N, means and response counts.

    The report wraps wide cells onto the lines above and below the data row, so
    cells are gathered from a vertical band and ordered by x position rather than
    by reading order.
    """
    page_index, y = row[0], row[1]
    counts, percents, words = [], [], []
    for other in rows:
        if other[0] != page_index or abs(other[1] - y) > CELL_TOL:
            continue
        for x, token in other[2]:
            if PCT_RE.match(token):
                percents.append(x)
            elif COUNT_RE.match(token):
                counts.append((x, int(COUNT_RE.match(token).group(1))))
            elif re.search(r"[A-Za-z]", token):
                words.append((other[1], x, token))

    question = re.sub(r"\s+", " ", " ".join(w for _y, _x, w in sorted(words))).strip()
    # One percentage and one count per cell, so x-order recovers the columns.
    cells = ([c for _x, c in sorted(counts, key=lambda z: z[0])]
             if len(counts) == len(percents) else None)
    return {"question": question, "n": int(match.group(1)),
            "mean": float(match.group(2)), "dept": float(match.group(3)),
            "college": float(match.group(4)), "cells": cells, "page": page_index + 1}


def distribution(cells, n):
    """Split a row of cells into 1-5 counts plus an excluded Neutral/NA count."""
    if cells is not None:
        for width in (5, 6):
            if len(cells) == width and sum(cells) == n:
                return cells[:5], (cells[5] if width == 6 else 0)
    return None, None


def collect(terms):
    """Validate and return per-term response distributions for each item in ITEMS."""
    data, problems = [], []
    for term in terms:
        # Respondents = the largest N on any item, i.e. the term's submission count,
        # since single items may go unanswered (Fall 2025: 17 responses, 16 on item 1).
        record = {"term": term["term"], "possible": term["possible"],
                  "respondents": max((i["n"] for i in term["items"]), default=0),
                  "items": {}}
        for key, label, pattern in ITEMS:
            matches = [i for i in term["items"] if re.search(pattern, i["question"])]
            if not matches:
                problems.append("%s: no item matching %r" % (term["term"], label))
                continue
            item = matches[0]
            counts, neutral = distribution(item["cells"], item["n"])
            if counts is None:
                problems.append("%s %s: counts %s do not sum to N=%d (p%d)"
                                % (term["term"], label, item["cells"], item["n"], item["page"]))
                continue
            scored = sum(counts)
            if scored == 0:
                problems.append("%s %s: no scored responses (p%d)"
                                % (term["term"], label, item["page"]))
                continue
            mean = sum((score + 1) * c for score, c in enumerate(counts)) / scored
            if abs(half_up(mean, 1) - item["mean"]) > 0.051:
                problems.append("%s %s: reconstructed mean %.3f but report says %s "
                                "(counts %s, p%d)"
                                % (term["term"], label, mean, item["mean"],
                                   counts, item["page"]))
                continue
            record["items"][key] = {"counts": counts, "neutral": neutral, "n": item["n"],
                                    "mean": item["mean"], "dept": item["dept"],
                                    "college": item["college"]}
        data.append(record)

    if problems:
        sys.exit("Error: the report did not parse cleanly, so nothing was written.\n  "
                 + "\n  ".join(problems))
    return data


def pool(data):
    """Pool student-level responses across every term."""
    stats = {}
    for key, label, _pattern in ITEMS:
        counts = [0] * 5
        dept_weighted = college_weighted = weight = 0.0
        for record in data:
            item = record["items"][key]
            for score in range(5):
                counts[score] += item["counts"][score]
            scored = sum(item["counts"])
            dept_weighted += item["dept"] * scored
            college_weighted += item["college"] * scored
            weight += scored
        n = sum(counts)
        mean = sum((score + 1) * c for score, c in enumerate(counts)) / n
        variance = (sum(c * ((score + 1) - mean) ** 2 for score, c in enumerate(counts))
                    / (n - 1)) if n > 1 else 0.0
        stats[key] = {"label": label, "n": n, "counts": counts, "mean": mean,
                      "sd": math.sqrt(variance),
                      "top2": (counts[3] + counts[4]) / n * 100,
                      "dept": dept_weighted / weight,
                      "college": college_weighted / weight}
    return stats


HEADER = """{% comment %}
  Generated by scripts/teaching_evals_to_html.py from the GW evaluation report.
  Edit the script (or rerun scripts/update_teaching_evals.sh), not this file.
{% endcomment %}
"""

TABLE = """{{% if include.course == "{course}" %}}
<details class="abs">
  <summary><b>Evaluations</b></summary>
  <div>
    <table>
      <thead>
        <tr>
          <th>Item (1&ndash;5 scale)</th>
          <th>Mean (% 4&ndash;5)</th>
          <th>Dept. avg.</th>
          <th>College avg.</th>
        </tr>
      </thead>
      <tbody>
{rows}
      </tbody>
    </table>
    <p><small>
      Pooled across {terms} offerings, {first} &ndash; {last}. {responded} of {possible}
      enrolled students responded ({rate}%); item-level <i>n</i> ranges from {n_min} to {n_max}.
      Means are computed over individual student responses, pooling all terms;
      parentheses give the share of respondents rating the item 4 or 5.
      Department and college averages are the GW-reported comparison means for
      the same items, weighted by this course's respondent counts.
    </small></p>
  </div>
</details>
{{% endif %}}
"""

ROW = ("        <tr><td>{label}</td><td>{mean:.2f} ({top2:.0f}%)</td>"
       "<td>{dept:.2f}</td><td>{college:.2f}</td></tr>")


def render(data, stats, course):
    responded = sum(r["respondents"] for r in data)
    possible = sum(r["possible"] for r in data)
    sizes = [stats[key]["n"] for key, _label, _pattern in ITEMS]
    rows = "\n".join(
        ROW.format(label=stats[key]["label"], mean=stats[key]["mean"],
                   top2=half_up(stats[key]["top2"]), dept=stats[key]["dept"],
                   college=stats[key]["college"])
        for key, _label, _pattern in ITEMS)
    return HEADER + TABLE.format(
        course=course, rows=rows, terms=len(data),
        first=data[0]["term"], last=data[-1]["term"],
        responded=responded, possible=possible,
        rate="%.0f" % half_up(responded / possible * 100.0),
        n_min=min(sizes), n_max=max(sizes))


def print_report(data, stats):
    print("Response rates by term")
    print("  %-13s%6s%10s%7s" % ("Term", "Resp", "Enrolled", "Rate"))
    for record in data:
        rate = record["respondents"] / record["possible"] * 100
        print("  %-13s%6d%10d%6.0f%%"
              % (record["term"], record["respondents"], record["possible"], rate))
    responded = sum(r["respondents"] for r in data)
    possible = sum(r["possible"] for r in data)
    print("  %-13s%6d%10d%6.1f%%"
          % ("TOTAL", responded, possible, responded / possible * 100))

    print("\nPer-term means")
    print("  %-13s" % "Term" + "".join("%8s" % k[:6] for k, _l, _p in ITEMS))
    for record in data:
        print("  %-13s" % record["term"]
              + "".join("%8.1f" % record["items"][k]["mean"] for k, _l, _p in ITEMS))

    print("\nPooled across all terms (student-level)")
    print("  %-28s%5s%7s%6s%7s%7s%7s"
          % ("Item", "n", "mean", "sd", "%4-5", "dept", "coll"))
    for key, _label, _pattern in ITEMS:
        s = stats[key]
        print("  %-28s%5d%7.2f%6.2f%6.0f%%%7.2f%7.2f"
              % (s["label"], s["n"], s["mean"], s["sd"], s["top2"], s["dept"], s["college"]))
        print("  %-28s%s" % ("  counts, 1 to 5:", s["counts"]))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.join(os.path.dirname(here), "_includes", "evals-toggle.html")

    parser = argparse.ArgumentParser(
        description="Build the aggregate course-evaluation table from a GW evaluation PDF.")
    parser.add_argument("--input", required=True,
                        help="GW evaluation report PDF (e.g. _All_Years.pdf)")
    parser.add_argument("--output", default=default_out, help="Jekyll include to write")
    parser.add_argument("--course", default="time_series_gwu",
                        help="course key the include guards on")
    parser.add_argument("--dry-run", action="store_true",
                        help="show the output without writing it")
    parser.add_argument("--report", action="store_true", help="also print per-term detail")
    parser.add_argument("--json", metavar="PATH", help="write the parsed per-term data here")
    args = parser.parse_args()

    pdf = os.path.expanduser(args.input)
    if not os.path.isfile(pdf):
        sys.exit("Error: PDF not found at %s" % pdf)

    data = collect(parse_terms(text_rows(pdf)))
    stats = pool(data)
    rendered = render(data, stats, args.course)

    print("Parsed %d terms from %s" % (len(data), pdf))
    print("  %s through %s; every term mean matches the value printed in the report.\n"
          % (data[0]["term"], data[-1]["term"]))
    if args.report:
        print_report(data, stats)
        print()

    if args.json:
        with io.open(os.path.expanduser(args.json), "w", encoding="utf-8") as handle:
            handle.write(json.dumps({"terms": data, "pooled": stats}, indent=1))
        print("Wrote parsed data to %s" % args.json)

    out = os.path.expanduser(args.output)
    previous = io.open(out, encoding="utf-8").read() if os.path.isfile(out) else ""
    if previous == rendered:
        print("%s is already up to date; nothing to do." % out)
        return

    diff = "".join(difflib.unified_diff(
        previous.splitlines(True), rendered.splitlines(True),
        fromfile="%s (current)" % out, tofile="%s (new)" % out))
    print(diff if diff else rendered)
    if args.dry_run:
        print("Dry run: nothing written.")
        return

    with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(rendered)
    print("Wrote %s" % out)


if __name__ == "__main__":
    main()
