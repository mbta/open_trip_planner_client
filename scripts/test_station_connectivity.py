import io
import importlib.util
import json
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch

import station_connectivity as audit


FIXTURE = Path(__file__).resolve().parents[1] / "test/support/station_connectivity_stops.txt"
OSM_FIXTURE = FIXTURE.with_name("station_connectivity.osm")


def outcome(status):
    return {"status": status, "routing_errors": []}


def probes(coordinate="no_connection", stop="no_connection"):
    return [
        {"endpoint": endpoint, "direction": direction, **outcome(status)}
        for endpoint, status in [("coordinate", coordinate), ("stop", stop)]
        for direction in ("outbound", "inbound")
        for _ in range(3)
    ]


class StationConnectivityTest(unittest.TestCase):
    def test_reads_platforms_not_parent_stations_entrances_or_standalone_bus_stops(self):
        platforms = audit.read_platforms(FIXTURE, [])
        self.assertEqual([p["stop_id"] for p in platforms], ["platform"])
        self.assertEqual(platforms[0]["station_id"], "station")
        self.assertEqual(len(audit.read_platforms(FIXTURE, ["station"])), 1)

    def test_unknown_station_filter_is_an_error(self):
        with self.assertRaisesRegex(ValueError, "Unknown station"):
            audit.read_platforms(FIXTURE, ["absent"])

    def test_matches_feed_ids_without_guessing_ambiguous_feeds(self):
        self.assertEqual(
            audit.match_stop("platform", ["feed:platform"], None), "feed:platform"
        )
        self.assertIsNone(audit.match_stop("absent", ["feed:platform"], None))
        with self.assertRaisesRegex(ValueError, "Ambiguous"):
            audit.match_stop("platform", ["a:platform", "b:platform"], None)
        self.assertEqual(
            audit.match_stop("platform", ["a:platform", "b:platform"], "b"),
            "b:platform",
        )

    def test_candidate_permissions_are_conservative(self):
        self.assertTrue(audit.walkable_target({"highway": "residential"}))
        self.assertTrue(
            audit.walkable_target(
                {"highway": "footway", "access": "private", "foot": "yes"}
            )
        )
        for tags in [
            {"railway": "platform"},
            {"highway": "footway", "public_transport": "platform"},
            {"highway": "residential", "foot": "no"},
            {"highway": "service", "access": "private"},
            {"highway": "construction"},
            {"highway": "pedestrian", "area": "yes"},
        ]:
            with self.subTest(tags=tags):
                self.assertFalse(audit.walkable_target(tags))

    def test_selects_separated_targets_and_excludes_nearby_platform(self):
        center = {"lat": 42.0, "lon": -71.0}
        candidates = [
            {"lat": 42.00001, "lon": -71.0, "node_id": 1},
            {"lat": 42.002, "lon": -71.0, "node_id": 2},
            {"lat": 42.00201, "lon": -71.0, "node_id": 3},
            {"lat": 41.998, "lon": -71.0, "node_id": 4},
            {"lat": 42.0, "lon": -70.997, "node_id": 5},
        ]
        targets = audit.select_targets(center, candidates, 100, 500, 4)
        self.assertEqual({t["node_id"] for t in targets}, {3, 4, 5})

    def test_classifies_only_controlled_disconnections_as_likely_islands(self):
        controls = [outcome("ok")] * 4
        self.assertEqual(audit.classify(probes(), controls, 3), "likely_isolated_platform")
        self.assertEqual(
            audit.classify(probes(), [outcome("no_connection")], 3), "inconclusive"
        )
        self.assertEqual(audit.classify(probes(), controls, 2), "inconclusive")
        self.assertEqual(
            audit.classify(probes("ok", "no_connection"), controls, 3),
            "possible_linking_or_snapping_problem",
        )
        self.assertEqual(
            audit.classify(probes("ok", "ok"), controls, 3), "connected"
        )
        self.assertEqual(
            audit.classify(probes("error", "no_connection"), controls, 3),
            "request_error",
        )

    def test_partial_failures_are_not_reported_as_connected(self):
        results = probes("ok", "ok")
        results[0]["status"] = "no_connection"
        self.assertEqual(
            audit.classify(results, [outcome("ok")] * 4, 3),
            "partial_or_directional_failure",
        )

    def test_probe_preserves_routing_errors_and_rejects_empty_success(self):
        client = audit.OtpClient("http://localhost:8080", timeout=1)
        origin = audit.coordinate({"lat": 42.0, "lon": -71.0})
        with patch.object(
            client,
            "graphql",
            return_value={
                "planConnection": {
                    "routingErrors": [{"code": "NO_DIRECT_MODE_CONNECTION"}],
                    "edges": [],
                }
            },
        ):
            result = client.probe(origin, origin)
            self.assertEqual(result["status"], "no_connection")
            self.assertEqual(result["routing_errors"][0]["code"], "NO_DIRECT_MODE_CONNECTION")
        with patch.object(
            client, "graphql", return_value={"planConnection": {"routingErrors": [], "edges": []}}
        ):
            self.assertEqual(client.probe(origin, origin)["status"], "error")

    def test_graphql_errors_are_not_silently_treated_as_missing_stops(self):
        client = audit.OtpClient("http://localhost:8080", timeout=1)
        response = io.BytesIO(json.dumps({"errors": [{"message": "bad query"}]}).encode())
        with patch("urllib.request.urlopen", return_value=response):
            with self.assertRaisesRegex(audit.RequestError, "bad query"):
                client.graphql("query { stops { gtfsId } }")

    def test_audit_exports_all_probes_and_controls(self):
        platform = {**audit.read_platforms(FIXTURE, [])[0], "otp_stop_id": "feed:platform"}
        targets = [
            {"lat": 42.525, "lon": -71.108, "node_id": 1},
            {"lat": 42.519, "lon": -71.108, "node_id": 2},
            {"lat": 42.522, "lon": -71.104, "node_id": 3},
        ]
        client = audit.OtpClient("http://localhost:8080", timeout=1)
        with patch.object(client, "probe", return_value=outcome("ok")) as probe:
            result = audit.audit_platform(client, platform, targets)
        self.assertEqual(probe.call_count, 16)
        self.assertEqual(len(result["controls"]), 4)
        self.assertEqual(len(result["probes"]), 12)
        self.assertEqual(result["classification"], "connected")
        stop_probes = [p for p in result["probes"] if p["endpoint"] == "stop"]
        self.assertIn(
            {"location": {"stopLocation": {"stopLocationId": "feed:platform"}}},
            [stop_probes[0]["origin"], stop_probes[0]["destination"]],
        )
        with patch.object(client, "probe") as probe:
            result = audit.audit_platform(client, {**platform, "otp_stop_id": None}, targets)
        probe.assert_not_called()
        self.assertEqual(result["classification"], "missing_otp_stop")

    def test_cli_writes_evidence_and_refuses_to_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            prefix = Path(directory) / "audit"
            args = [
                "--stops", str(FIXTURE), "--osm", str(OSM_FIXTURE),
                "--otp-url", "http://localhost:8080", "--output", str(prefix),
            ]
            with patch.object(
                audit.OtpClient, "graphql", return_value={"stops": [{"gtfsId": "feed:platform"}]}
            ), patch.object(
                audit.OtpClient, "server_info", return_value={"version": {"version": "test"}}
            ), patch.object(audit, "load_targets", return_value=[[]]), redirect_stdout(
                io.StringIO()
            ), redirect_stderr(io.StringIO()):
                self.assertEqual(audit.main(args), 0)
                with self.assertRaises(SystemExit) as exc:
                    audit.main(args)
                self.assertEqual(exc.exception.code, 2)
            records = [json.loads(line) for line in Path(str(prefix) + ".jsonl").read_text().splitlines()]
            self.assertEqual(records[0]["type"], "metadata")
            self.assertEqual(records[1]["classification"], "inconclusive")
            self.assertIn("platform", Path(str(prefix) + ".csv").read_text())

    @unittest.skipUnless(importlib.util.find_spec("osmium"), "Install PBF reader for integration test")
    def test_reads_real_pbf_and_excludes_platforms_and_private_ways(self):
        import osmium

        with tempfile.TemporaryDirectory() as directory:
            pbf = Path(directory) / "sample.osm.pbf"
            with osmium.SimpleWriter(str(pbf)) as writer:
                class Copy(osmium.SimpleHandler):
                    def node(self, node):
                        writer.add_node(node)

                    def way(self, way):
                        writer.add_way(way)

                Copy().apply_file(str(OSM_FIXTURE))
            with redirect_stderr(io.StringIO()):
                targets = audit.load_targets(pbf, audit.read_platforms(FIXTURE, []), 100, 500, 3)
            self.assertEqual(len(targets[0]), 3)
            self.assertEqual({t["way_id"] for t in targets[0]}, {1, 2, 3})

    def test_version_metadata_failure_is_explicit_and_does_not_block_probes(self):
        client = audit.OtpClient("http://localhost:8080", timeout=1)
        with patch("urllib.request.urlopen", side_effect=OSError("unreachable")), redirect_stderr(
            io.StringIO()
        ) as errors:
            self.assertIn("unreachable", client.server_info()["error"])
        self.assertIn("Could not read OTP version", errors.getvalue())

    def test_interruption_prevents_further_network_probes(self):
        client = audit.OtpClient("http://localhost:8080", timeout=1)
        client.cancelled.set()
        with patch.object(client, "graphql") as graphql:
            with self.assertRaises(InterruptedError):
                client.probe({}, {})
        graphql.assert_not_called()


if __name__ == "__main__":
    unittest.main()
