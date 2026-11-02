#!/usr/bin/env python3
"""Redact absolute URLs and common credential forms from public CI logs."""
import re
import sys

URL = re.compile(r'https?://[^\s"<>]+', re.IGNORECASE)
BEARER = re.compile(r'\bBearer\s+[^\s,;]+', re.IGNORECASE)
ASSIGNMENT = re.compile(
    r'\b(authorization|api[_-]?key|access[_-]?token|token)(\s*[:=]\s*)[^\s,;]+',
    re.IGNORECASE,
)
SECRET_PREFIX = re.compile(r'\bsk-[A-Za-z0-9_-]{16,}\b')

for line in sys.stdin:
    line = URL.sub('[URL REDACTED]', line)
    line = BEARER.sub('Bearer [REDACTED]', line)
    line = ASSIGNMENT.sub(lambda match: match.group(1) + match.group(2) + '[REDACTED]', line)
    line = SECRET_PREFIX.sub('[API KEY REDACTED]', line)
    sys.stdout.write(line)
