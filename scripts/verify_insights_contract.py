#!/usr/bin/env python3
"""Validate optional insights or an explicitly supported temporary outage."""
import json
import os
import sys


def verify(status, path, strict=False):
    if status in (502, 503, 504) and not strict:
        return f"::warning::Optional insights unavailable (HTTP {status}); degraded-state tests remain required."
    if status != 200:
        raise SystemExit(f"Insights request failed: HTTP {status}")
    with open(path) as file:
        data = json.load(file)
    if data.get("schema") != 1:
        raise SystemExit(
            f"api/radar-insights: expected schema 1, got {data.get('schema')!r}"
        )
    recommendations = data.get("recommendations")
    if not isinstance(recommendations, list) or not recommendations:
        raise SystemExit(
            "api/radar-insights: expected at least one recommendation group"
        )
    items = []
    for group in recommendations:
        if not isinstance(group, dict) or not isinstance(group.get("items"), list):
            raise SystemExit(
                "api/radar-insights: invalid recommendation group"
            )
        items.extend(group["items"])
    if not items:
        raise SystemExit(
            "api/radar-insights: expected at least one recommendation item"
        )
    alerts = data.get("degradation_alerts", {})
    if isinstance(alerts, list):
        alert_items = alerts
    elif isinstance(alerts, dict) and isinstance(alerts.get("items", []), list):
        alert_items = alerts.get("items", [])
    else:
        raise SystemExit(
            "api/radar-insights: invalid degradation_alerts shape"
        )
    return f"{len(recommendations)} groups, {len(items)} recommendations, {len(alert_items)} alerts"


if __name__ == "__main__":
    print(verify(int(sys.argv[1]), sys.argv[2], os.environ.get("CODEX_RADAR_STRICT_INSIGHTS") == "1"))
