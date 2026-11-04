#!/usr/bin/env python3
"""Read-only GTFS/OSM audit of walking connectivity on a running OTP server."""

import argparse
import csv
import json
import math
import sys
import urllib.error
import urllib.request
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path
from threading import Event


PLAN_QUERY = """
query Connectivity($origin: PlanLabeledLocationInput!,
                   $destination: PlanLabeledLocationInput!) {
  planConnection(origin: $origin, destination: $destination,
                 modes: {direct: [WALK], directOnly: true}, first: 1) {
    routingErrors { code description inputField }
    edges { node {
      duration walkDistance
      legs {
        mode distance
        from { lat lon name }
        to { lat lon name }
        legGeometry { points }
        steps { streetName distance relativeDirection }
      }
    } }
  }
}
"""

CSV_FIELDS = [
    "station_id", "station_name", "stop_id", "stop_name", "otp_stop_id",
    "lat", "lon", "classification", "target_count", "error",
]


class RequestError(Exception):
    """A network, GraphQL, or unexpected OTP response error."""


def distance(a, b):
    lat1, lat2 = math.radians(a["lat"]), math.radians(b["lat"])
    dlat = lat2 - lat1
    dlon = math.radians(b["lon"] - a["lon"])
    hav = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 6371000 * 2 * math.asin(min(1, math.sqrt(hav)))


def read_platforms(path, station_ids):
    with open(path, newline="", encoding="utf-8-sig") as source:
        reader = csv.DictReader(source)
        required = {"stop_id", "stop_name", "stop_lat", "stop_lon", "location_type", "parent_station"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError(f"stops.txt must contain columns {sorted(required)}")
        rows = list(reader)
    if len({r["stop_id"] for r in rows}) != len(rows):
        raise ValueError("Duplicate stop_id in stops.txt")
    stations = {r["stop_id"]: r for r in rows if r["location_type"] == "1"}
    unknown = set(station_ids) - stations.keys()
    if unknown:
        raise ValueError(f"Unknown station IDs: {sorted(unknown)}")
    selected = set(station_ids) if station_ids else set(stations)
    platforms = []
    for row in rows:
        parent = row["parent_station"]
        if parent not in selected or row["location_type"] not in ("", "0"):
            continue
        try:
            lat, lon = float(row["stop_lat"]), float(row["stop_lon"])
        except ValueError as exc:
            raise ValueError(f"Invalid coordinates for {row['stop_id']}") from exc
        if not (-90 < lat < 90 and -180 <= lon <= 180):
            raise ValueError(f"Invalid coordinates for {row['stop_id']}")
        platforms.append({
            "station_id": parent,
            "station_name": stations[parent]["stop_name"],
            "stop_id": row["stop_id"],
            "stop_name": row["stop_name"],
            "lat": lat,
            "lon": lon,
        })
    missing = selected - {p["station_id"] for p in platforms}
    if missing:
        raise ValueError(f"Stations without child platforms in stops.txt: {sorted(missing)}")
    if not platforms:
        raise ValueError("No station platforms found in stops.txt")
    return platforms


def match_stop(stop_id, otp_ids, feed_id):
    matches = [
        identifier for identifier in otp_ids
        if identifier.partition(":")[2] == stop_id
        and (feed_id is None or identifier.partition(":")[0] == feed_id)
    ]
    if len(matches) > 1:
        raise ValueError(f"Ambiguous OTP feeds for {stop_id}; specify --feed-id")
    return matches[0] if matches else None


def walkable_target(tags):
    # Candidate selection only; OTP control routes verify actual connectivity.
    allowed = {
        "residential", "unclassified", "living_street", "tertiary", "secondary",
        "primary", "service", "pedestrian", "footway", "path", "steps",
    }
    if tags.get("highway") not in allowed or tags.get("area") == "yes":
        return False
    if tags.get("railway") == "platform" or tags.get("public_transport") == "platform":
        return False
    foot = tags.get("foot")
    if foot in ("yes", "designated", "permissive"):
        return True
    return foot is None and tags.get("access", "yes") in ("yes", "permissive")


def sector(center, point):
    east = (point["lon"] - center["lon"]) * math.cos(math.radians(center["lat"]))
    north = point["lat"] - center["lat"]
    return int((math.atan2(east, north) + math.pi) / (math.pi / 4)) % 8


def select_targets(center, candidates, minimum, maximum, count):
    desired = (minimum + maximum) / 2
    eligible = [
        {**p, "distance_from_platform_m": round(distance(center, p), 1)}
        for p in candidates if minimum <= distance(center, p) <= maximum
    ]
    eligible.sort(key=lambda p: abs(p["distance_from_platform_m"] - desired))
    chosen = []
    used_sectors = set()
    for point in eligible:
        direction = sector(center, point)
        if direction in used_sectors or any(distance(point, other) < minimum for other in chosen):
            continue
        chosen.append(point)
        used_sectors.add(direction)
        if len(chosen) == count:
            break
    return chosen


def load_targets(path, platforms, minimum, maximum, count):
    try:
        import osmium
    except ImportError as exc:
        raise ValueError(
            "Missing PBF reader. Install scripts/station_connectivity_requirements.txt "
            "in a virtual environment (see README)."
        ) from exc

    cell_size = maximum / 110000
    index = defaultdict(list)
    for i, point in enumerate(platforms):
        lat_delta = maximum / 110000
        lon_delta = lat_delta / max(0.01, math.cos(math.radians(point["lat"])))
        for x in range(math.floor((point["lat"] - lat_delta) / cell_size),
                       math.floor((point["lat"] + lat_delta) / cell_size) + 1):
            for y in range(math.floor((point["lon"] - lon_delta) / cell_size),
                           math.floor((point["lon"] + lon_delta) / cell_size) + 1):
                index[x, y].append(i)
    candidates = [dict() for _ in platforms]

    class Streets(osmium.SimpleHandler):
        def way(self, way):
            tags = dict(way.tags)
            if not walkable_target(tags):
                return
            for node in way.nodes:
                if not node.location.valid():
                    raise ValueError(f"OSM way {way.id} has missing node locations")
                cell = math.floor(node.lat / cell_size), math.floor(node.lon / cell_size)
                for i in index.get(cell, []):
                    point = {
                        "lat": node.lat, "lon": node.lon, "node_id": node.ref,
                        "way_id": way.id, "name": tags.get("name", tags["highway"]),
                    }
                    separation = distance(platforms[i], point)
                    if minimum <= separation <= maximum:
                        direction = sector(platforms[i], point)
                        previous = candidates[i].get(direction)
                        desired = (minimum + maximum) / 2
                        if previous is None or abs(separation - desired) < abs(
                            distance(platforms[i], previous) - desired
                        ):
                            candidates[i][direction] = point

    print("Reading OSM ways (this can take several minutes)...", file=sys.stderr)
    Streets().apply_file(str(path), locations=True, idx="flex_mem")
    return [
        select_targets(p, list(points.values()), minimum, maximum, count)
        for p, points in zip(platforms, candidates)
    ]


def coordinate(point):
    return {"location": {"coordinate": {"latitude": point["lat"], "longitude": point["lon"]}}}


class OtpClient:
    def __init__(self, base_url, timeout):
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.cancelled = Event()

    def server_info(self):
        try:
            with urllib.request.urlopen(self.base_url + "/otp", timeout=self.timeout) as response:
                info = json.load(response)
            if not isinstance(info, dict) or "version" not in info:
                raise ValueError("OTP info endpoint did not return version metadata")
            return info
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            message = f"Could not read OTP version metadata: {exc}"
            print(message, file=sys.stderr)
            return {"error": message}

    def graphql(self, query, variables=None):
        request = urllib.request.Request(
            self.base_url + "/otp/routers/default/index/graphql",
            data=json.dumps({"query": query, "variables": variables or {}}).encode(),
            headers={"Content-Type": "application/json", "Accept": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                payload = json.load(response)
        except (urllib.error.URLError, TimeoutError, OSError, ValueError) as exc:
            raise RequestError(f"OTP request failed: {exc}") from exc
        if not isinstance(payload, dict) or payload.get("errors") or not isinstance(payload.get("data"), dict):
            raise RequestError(f"Invalid GraphQL response: {json.dumps(payload)}")
        return payload["data"]

    def probe(self, origin, destination):
        if self.cancelled.is_set():
            raise InterruptedError("Audit interrupted")
        try:
            data = self.graphql(PLAN_QUERY, {"origin": origin, "destination": destination})
            plan = data.get("planConnection")
            if not isinstance(plan, dict):
                raise RequestError("Missing planConnection in OTP response")
            errors, edges = plan.get("routingErrors"), plan.get("edges")
            if not isinstance(errors, list) or not isinstance(edges, list):
                raise RequestError("Missing routingErrors or edges in OTP response")
            status = "error"
            if not errors and edges:
                status = "ok"
            elif errors and not edges and all(
                error.get("code") == "NO_DIRECT_MODE_CONNECTION" for error in errors
            ):
                status = "no_connection"
            return {
                "status": status, "routing_errors": errors, "itineraries": edges,
                "error": None if status != "error" else "Unexpected or unsuccessful routing response",
            }
        except RequestError as exc:
            return {"status": "error", "routing_errors": [], "error": str(exc)}


def classify(probes, controls, target_count):
    if any(p["status"] == "error" for p in probes + controls):
        return "request_error"
    if target_count < 3 or len(controls) < 2 * (target_count - 1) or any(
        p["status"] != "ok" for p in controls
    ):
        return "inconclusive"
    coordinate_statuses = {p["status"] for p in probes if p["endpoint"] == "coordinate"}
    stop_statuses = {p["status"] for p in probes if p["endpoint"] == "stop"}
    if not coordinate_statuses or not stop_statuses:
        return "inconclusive"
    if coordinate_statuses == stop_statuses == {"no_connection"}:
        return "likely_isolated_platform"
    if coordinate_statuses == stop_statuses == {"ok"}:
        return "connected"
    if coordinate_statuses.isdisjoint(stop_statuses):
        return "possible_linking_or_snapping_problem"
    return "partial_or_directional_failure"


def audit_platform(client, platform, targets):
    result = {
        **platform, "targets": targets, "target_count": len(targets),
        "controls": [], "probes": [], "error": "",
    }
    if not platform["otp_stop_id"]:
        return {**result, "classification": "missing_otp_stop"}
    if len(targets) < 3:
        return {**result, "classification": "inconclusive", "error": "Fewer than three street targets"}
    for i in range(1, len(targets)):
        for a, b in [(0, i), (i, 0)]:
            result["controls"].append({
                "origin_target": a, "destination_target": b,
                **client.probe(coordinate(targets[a]), coordinate(targets[b])),
            })
    locations = {
        "coordinate": coordinate(platform),
        "stop": {"location": {"stopLocation": {"stopLocationId": platform["otp_stop_id"]}}},
    }
    for endpoint, location in locations.items():
        for i, target in enumerate(targets):
            street = coordinate(target)
            for direction, origin, destination in [
                ("outbound", location, street), ("inbound", street, location),
            ]:
                result["probes"].append({
                    "endpoint": endpoint, "target": i, "direction": direction,
                    "origin": origin, "destination": destination,
                    **client.probe(origin, destination),
                })
    result["classification"] = classify(result["probes"], result["controls"], len(targets))
    result["error"] = "; ".join(sorted({
        p["error"] for p in result["controls"] + result["probes"] if p.get("error")
    }))
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stops", required=True, type=Path, help="GTFS stops.txt")
    parser.add_argument("--osm", required=True, type=Path, help="Local .osm.pbf extract")
    parser.add_argument("--otp-url", required=True, help="OTP server base URL, e.g. http://localhost:8080")
    parser.add_argument("--output", required=True, type=Path, help="Output prefix for .csv and .jsonl files")
    parser.add_argument("--station", action="append", default=[], help="GTFS parent station ID; repeatable")
    parser.add_argument("--feed-id", help="OTP feed ID, required if stop IDs match multiple feeds")
    parser.add_argument("--min-distance", type=float, default=100, help="Minimum target distance in metres")
    parser.add_argument("--max-distance", type=float, default=500, help="Maximum target distance in metres")
    parser.add_argument("--targets", type=int, default=3, help="Street targets per platform (3-8)")
    parser.add_argument("--workers", type=int, default=2, help="Concurrent platform audits (1-8)")
    parser.add_argument("--timeout", type=float, default=30, help="Timeout per HTTP request in seconds")
    args = parser.parse_args(argv)
    if not (0 < args.min_distance < args.max_distance and math.isfinite(args.max_distance)):
        parser.error("Require 0 < --min-distance < --max-distance, both finite")
    if not (3 <= args.targets <= 8 and 1 <= args.workers <= 8 and 0 < args.timeout < math.inf):
        parser.error("Require 3-8 targets, 1-8 workers, and a positive finite timeout")
    if not args.otp_url.startswith(("http://", "https://")):
        parser.error("--otp-url must be an HTTP(S) server base URL")
    for path in (args.stops, args.osm):
        if not path.is_file():
            parser.error(f"Input file not found: {path}")
    csv_path = Path(str(args.output) + ".csv")
    json_path = Path(str(args.output) + ".jsonl")
    if csv_path.exists() or json_path.exists():
        parser.error("Output already exists; choose a different --output prefix")

    try:
        platforms = read_platforms(args.stops, args.station)
        client = OtpClient(args.otp_url, args.timeout)
        inventory = client.graphql("query { stops { gtfsId } }")
        if not isinstance(inventory.get("stops"), list):
            raise RequestError("OTP did not return a stop inventory")
        otp_ids = [s["gtfsId"] for s in inventory["stops"]]
        for platform in platforms:
            platform["otp_stop_id"] = match_stop(platform["stop_id"], otp_ids, args.feed_id)
        if not any(p["otp_stop_id"] for p in platforms):
            raise ValueError("No GTFS platform IDs match OTP; check --feed-id and input feed")
        targets = load_targets(
            args.osm, platforms, args.min_distance, args.max_distance, args.targets
        )
        metadata = {
            "type": "metadata", "started_at": datetime.now(timezone.utc).isoformat(),
            "otp_url": args.otp_url, "feed_id": args.feed_id,
            "stops_file": str(args.stops), "osm_file": str(args.osm),
            "stops_mtime": args.stops.stat().st_mtime, "osm_mtime": args.osm.stat().st_mtime,
            "min_distance_m": args.min_distance, "max_distance_m": args.max_distance,
            "targets": args.targets, "workers": args.workers, "timeout": args.timeout,
            "otp_info": client.server_info(),
        }
        counts = Counter()
        with csv_path.open("x", newline="", encoding="utf-8") as csv_file, json_path.open(
            "x", encoding="utf-8"
        ) as json_file, ThreadPoolExecutor(max_workers=args.workers) as executor:
            writer = csv.DictWriter(csv_file, fieldnames=CSV_FIELDS, extrasaction="ignore")
            writer.writeheader()
            json_file.write(json.dumps(metadata) + "\n")
            results = executor.map(
                lambda pair: audit_platform(client, *pair), zip(platforms, targets)
            )
            try:
                for result in results:
                    writer.writerow(result)
                    json_file.write(json.dumps({"type": "platform", **result}) + "\n")
                    csv_file.flush()
                    json_file.flush()
                    counts[result["classification"]] += 1
                    print(
                        f"{result['stop_id']}: {result['classification']}",
                        file=sys.stderr,
                    )
            except KeyboardInterrupt:
                client.cancelled.set()
                executor.shutdown(wait=True, cancel_futures=True)
                raise
        print(json.dumps({"platforms": len(platforms), "classifications": counts}, indent=2))
        return 2 if counts["request_error"] or counts["missing_otp_stop"] else 0
    except (ValueError, RequestError, OSError, RuntimeError) as exc:
        print(f"Audit failed: {exc}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("Audit interrupted; completed platform records are preserved.", file=sys.stderr)
        return 130


if __name__ == "__main__":
    sys.exit(main())
