#!/usr/bin/env python3
"""Self-test for parity_report.py scoring and no-invention guarantees."""
import json
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).parent
CHECKLIST = HERE.parent.parent / "docs" / "comic-translation" / "ascent-parity.json"


def main():
    with tempfile.TemporaryDirectory() as tmp:
        # 1) With full evidence every testable feature is proven.
        full = Path(tmp) / "full.json"
        full.write_text(json.dumps({"passed_tests": ["bridge", "decoder", "simulator", "live"]}))
        subprocess.run([sys.executable, str(HERE / "parity_report.py"), str(CHECKLIST),
                        str(full), str(Path(tmp) / "p1.json"), str(Path(tmp) / "p1.md")], check=True)
        report = json.loads((Path(tmp) / "p1.json").read_text())
        assert report["score_percent"] >= 90.0, report["score_percent"]
        assert report["missing_features"], "gaps must stay declared even at high score"

        # 2) With no evidence nothing is invented: everything untestable scores 0.
        empty = Path(tmp) / "empty.json"
        empty.write_text("{}")
        subprocess.run([sys.executable, str(HERE / "parity_report.py"), str(CHECKLIST),
                        str(empty), str(Path(tmp) / "p2.json"), str(Path(tmp) / "p2.md")], check=True)
        bare = json.loads((Path(tmp) / "p2.json").read_text())
        assert bare["score_percent"] == 0.0, bare["score_percent"]
        assert bare["documented_only"], "documented-only features must be listed without scoring"
        assert any("غير مثبت" in f["state"] for f in bare["features"] if f["status"] != "missing")

        # 3) The report file is real Arabic markdown with a table.
        text = (Path(tmp) / "p1.md").read_text()
        assert "درجة التكافؤ" in text and "| القدرة |" in text
    print("parity self-test ok: full=scored, empty=0.0, no invented proof")


if __name__ == "__main__":
    main()
