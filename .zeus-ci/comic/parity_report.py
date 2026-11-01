#!/usr/bin/env python3
"""Ascent parity report generator.

Reads the declared parity checklist (ascent-parity.json) plus the actual
evidence produced by CI (which tests ran and passed), and emits a machine
report (parity.json) and an Arabic markdown report (PARITY-CI.ar.md).

The tool never invents results: a capability counts as met only when the
evidence file proves the referenced test ran green in this run. Static
"documentation-only" capabilities are listed separately as unproven.
"""
import json
import sys
from pathlib import Path

WEIGHTS = {"yes": 1.0, "yes-simulator-vision": 0.9, "yes-static-catalog": 0.95,
           "yes-bounded": 0.9, "improved-interior-wcag": 1.0, "improved-arabic-fallback": 1.0,
           "yes-google-edge-mymemory": 0.95, "yes-user-key": 0.9, "yes-import": 0.9,
           "partial-inproc": 0.5, "missing": 0.0, "out-of-scope": None}


def load(path):
    return json.loads(Path(path).read_text())


def main(checklist_path, evidence_path, out_json, out_md):
    checklist = load(checklist_path)
    evidence = load(evidence_path) if evidence_path and Path(evidence_path).exists() else {}
    passed = set(evidence.get("passed_tests", []))
    rows = []
    met = unproven = missing = 0.0
    documented = []
    for feature in checklist["features"]:
        status = feature["zeus_status"]
        weight = WEIGHTS.get(status, 0.0)
        tests = {"bridge": "bridge", "decoder": "decoder", "simulator": "simulator",
                 "unit": "simulator", "live": "live", "none": None}.get(feature["zeus_test"])
        if tests is None:
            # Declared, not machine-testable here — listed, never scored.
            documented.append(feature["name"])
            rows.append((feature, "موثق في المصدر دون اختبار آلي في CI", "—"))
            continue
        proven = tests in passed
        if weight is None:
            state = "خارج النطاق (قارئ مستقل — تطبيق منفصل لاحقاً)"
            rows.append((feature, state, "—"))
            continue
        if proven:
            met += weight
            state = "مثبت في هذا التشغيل"
            rows.append((feature, state, f"{weight:.2f}"))
        else:
            unproven += weight
            state = "غير مثبت في هذا التشغيل"
            rows.append((feature, state, "0"))
        if status in ("missing",):
            missing += 1
    total = met + unproven
    score = (met / total * 100) if total else 0.0
    out = {
        "ascent_version": checklist["ascent_version"],
        "score_percent": round(score, 1),
        "proven_weight": round(met, 2),
        "unproven_weight": round(unproven, 2),
        "missing_features": [f["name"] for f in checklist["features"] if f["zeus_status"] == "missing"],
        "documented_only": documented,
        "out_of_scope": [f["name"] for f in checklist["features"] if f["zeus_status"] == "out-of-scope"],
        "features": [{"id": f["id"], "name": f["name"], "status": f["zeus_status"],
                      "state": state, "weight": w} for f, state, w in rows],
    }
    Path(out_json).write_text(json.dumps(out, ensure_ascii=False, indent=1))
    lines = [
        "# تقرير التكافؤ مع Ascent — هذا التشغيل",
        "",
        f"- النسخة المرجعية: Ascent {checklist['ascent_version']} (تحليل REA موثق).",
        f"- **درجة التكافؤ المثبتة: {score:.1f}%** من الوزن الكلي القابل للقياس.",
        f"- مثبت في هذا التشغيل: {met:.2f} · غير مثبت (لم يُشغّل اختباره هنا): {unproven:.2f}",
        "",
        "| القدرة | الحالة في هذا التشغيل | الوزن |",
        "|---|---|---|",
    ]
    for feature, state, weight in rows:
        lines.append(f"| {feature['name']} | {state} | {weight} |")
    if out["missing_features"]:
        lines += ["", "## ما يفتقده ZEUS بعد (فجوات حقيقية)"]
        lines += [f"- {name}" for name in out["missing_features"]]
    if out["documented_only"]:
        lines += ["", "## موثق في المصدر دون اختبار آلي (لا تدخل الدرجة)"]
        lines += [f"- {name}" for name in out["documented_only"]]
    lines += ["", "## خارج النطاق عمداً", ""]
    lines += [f"- {name}" for name in out["out_of_scope"]]
    lines += ["",
              "> الأداة لا تخترع نتائج: كل بند «مثبت» مرتبط باختبار أخضر في هذا التشغيل نفسه،",
              "> والبنود غير المقاسة تبقى معلنة كغير مثبتة. القياس الصوتي الحقيقي (CER على عينات فعلية) يبقى معيار القبول النهائي وفق compare.py."]
    Path(out_md).write_text("\n".join(lines))
    print(f"parity score: {score:.1f}% (proven {met:.2f} / {total:.2f})")


if __name__ == "__main__":
    main(*sys.argv[1:5])
