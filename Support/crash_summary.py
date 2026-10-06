#!/usr/bin/env python3
"""Prints the useful part of a macOS crash report (.ips): what killed the app and where.

Usage: crash_summary.py <report.ips>
"""
import json
import sys


def main(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    # An .ips file is one JSON header line followed by a JSON body.
    header_line, _, body_text = text.partition("\n")
    try:
        header = json.loads(header_line)
        body = json.loads(body_text)
    except ValueError:
        print(text[:4000])
        return

    print("Report:    ", path)
    print("When:      ", header.get("timestamp", body.get("captureTime", "?")))
    print("Version:   ", header.get("app_version", "?"), "·", header.get("os_version", "?"))
    exception = body.get("exception", {})
    if exception:
        print("Exception: ", exception.get("type", "?"), exception.get("signal", ""), exception.get("subtype", ""))
    termination = body.get("termination", {})
    if termination:
        print("Ended by:  ", termination.get("namespace", "?"), termination.get("indicator", ""),
              "·", termination.get("byProc", ""))
        for reason in termination.get("reasons", []):
            print("           ", reason)
    for image, messages in (body.get("asi") or {}).items():
        for message in messages:
            print("Message:   ", image, "→", message)

    images = body.get("usedImages", [])
    threads = body.get("threads", [])
    faulting = body.get("faultingThread")
    if faulting is None or faulting >= len(threads):
        return
    thread = threads[faulting]
    print()
    print("Crashed thread", faulting, "(" + (thread.get("queue") or thread.get("name") or "") + "):")
    for index, frame in enumerate(thread.get("frames", [])[:30]):
        image = images[frame["imageIndex"]] if frame.get("imageIndex", -1) < len(images) else {}
        name = image.get("name", "?")
        symbol = frame.get("symbol", "0x%x" % frame.get("imageOffset", 0))
        print("  %2d  %-28s %s" % (index, name, symbol))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
