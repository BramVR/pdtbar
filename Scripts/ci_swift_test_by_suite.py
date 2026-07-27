#!/usr/bin/env python3
"""Run SwiftPM tests in suite shards so CI cannot hang inside one aggregate run."""

from __future__ import annotations

import argparse
import glob
import os
import re
import signal
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from collections import Counter
from collections.abc import Iterable
from dataclasses import dataclass


@dataclass(frozen=True)
class TestSelection:
    name: str
    filter_pattern: str
    suite_name: str | None = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--group-size", type=int, default=12)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--limit-groups", type=int)
    parser.add_argument("--shard-index", type=int)
    parser.add_argument("--shard-count", type=int)
    parser.add_argument("--list-only", action="store_true")
    parser.add_argument("--swift-command", default="swift")
    parser.add_argument("--swift-command-arg", action="append", default=[])
    return parser.parse_args()


def run_command(command: list[str], timeout: int | None = None) -> int:
    print(f"+ {' '.join(command)}", flush=True)
    process = subprocess.Popen(command, start_new_session=True)
    try:
        return process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f"::warning::Command timed out after {timeout}s: {' '.join(command)}", flush=True)
        kill_process_group(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            kill_process_group(process.pid, signal.SIGKILL)
            process.wait()
        return 124


def kill_process_group(pid: int, sig: int) -> None:
    try:
        os.killpg(pid, sig)
    except ProcessLookupError:
        pass


def swift_test_list(swift_command: list[str]) -> tuple[list[TestSelection], dict[str, int]]:
    command = [*swift_command, "test", "list"]
    try:
        result = subprocess.run(command, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as error:
        print(f"+ {swift_command[0]} test list", flush=True)
        if error.stdout:
            print(error.stdout, end="" if error.stdout.endswith("\n") else "\n", flush=True)
        if error.stderr:
            print(error.stderr, end="" if error.stderr.endswith("\n") else "\n", file=sys.stderr, flush=True)
        raise
    selections: set[TestSelection] = set()
    counts: Counter[str] = Counter()
    unknown: list[str] = []
    for raw_line in result.stdout.splitlines():
        line = raw_line.strip()
        if not line or is_swiftpm_chatter(line):
            continue
        top_level = re.fullmatch(r"(?P<module>[^.]+)\.(?:`(?P<display>.+)`|(?P<function>[^()/]+))\(\)", line)
        if top_level is not None:
            module = top_level.group("module")
            test_name = top_level.group("display") or top_level.group("function")
            selections.add(
                TestSelection(
                    name=line,
                    # SwiftPM matches top-level Swift Testing functions by their display name,
                    # not the backtick-wrapped identifier printed by `swift test list`.
                    filter_pattern=rf"^{re.escape(module)}\..*{re.escape(test_name)}\(\)$",
                )
            )
            counts[line] += 1
            continue

        if "/" in line:
            suite = line.split("/", 1)[0]
            if "." in suite:
                selections.add(
                    TestSelection(
                        name=suite,
                        filter_pattern=rf"^{re.escape(suite)}/",
                        suite_name=suite,
                    )
                )
                counts[suite] += 1
                continue

        if re.fullmatch(r"[^.]+\.[^()/]+", line):
            selections.add(
                TestSelection(
                    name=line,
                    filter_pattern=rf"^{re.escape(line)}/",
                    suite_name=line,
                )
            )
            counts[line] += 1
            continue

        unknown.append(line)

    if unknown:
        rendered = "\n".join(f"- {line}" for line in unknown)
        raise RuntimeError(f"Unrecognized `swift test list` output:\n{rendered}")
    if not selections:
        raise RuntimeError("No test selections found in `swift test list` output")
    return sorted(selections, key=lambda selection: selection.name), dict(counts)


def is_swiftpm_chatter(line: str) -> bool:
    return (
        line.startswith("[")
        or line.startswith("Building ")
        or line.startswith("Build complete!")
        or line.startswith("warning:")
    )


def chunks(items: list[TestSelection], size: int) -> Iterable[list[TestSelection]]:
    for index in range(0, len(items), size):
        yield items[index : index + size]


def shard_groups(groups: list[list[TestSelection]], shard_index: int | None, shard_count: int | None) -> list[list[TestSelection]]:
    if shard_index is None and shard_count is None:
        return groups
    if shard_index is None or shard_count is None:
        raise ValueError("--shard-index and --shard-count must be passed together")
    if shard_count < 1:
        raise ValueError("--shard-count must be positive")
    if shard_index < 0 or shard_index >= shard_count:
        raise ValueError("--shard-index must be in the range [0, --shard-count)")
    return [group for index, group in enumerate(groups) if index % shard_count == shard_index]


def filter_for(suites: list[TestSelection]) -> str:
    return rf"({'|'.join(suite.filter_pattern for suite in suites)})"


def run_group(
    suites: list[TestSelection],
    timeout: int,
    swift_command: list[str],
) -> tuple[int, int | None, int | None]:
    with tempfile.TemporaryDirectory(prefix="pdtbar-swift-test-") as temporary_directory:
        output_path = os.path.join(temporary_directory, "results.xml")
        code = run_command(
            [
                *swift_command,
                "test",
                "--no-parallel",
                "--filter",
                filter_for(suites),
                "--xunit-output",
                output_path,
            ],
            timeout=timeout,
        )
        # Invariant: this package is Swift Testing only (no XCTest, one test target),
        # and SwiftPM writes the Swift Testing report to the requested path under
        # `--no-parallel`. `--no-parallel` is deliberate — see .github/workflows/ci.yml:
        # raw parallel `swift test` is flaky on shared runners. If XCTest is ever added
        # here, revisit reporting: SwiftPM emits XCTest xUnit only via its parallel
        # runner, so counts would come up short and shards would fail loudly with the
        # mismatch error below. That is fail-closed, but it needs a real fix, not a
        # relaxed assertion.
        #
        # Collect every report the run produced rather than only `output_path`.
        # SwiftPM writes Swift Testing results straight to the requested path here,
        # but when XCTest and Swift Testing both report it splits them across
        # `results.xml` and a `results-swift-testing.xml` sibling so the two cannot
        # collide. The directory is per-run and otherwise empty, so summing every
        # report in it is correct under either contract.
        report_paths = sorted(glob.glob(os.path.join(temporary_directory, "*.xml")))
        if not report_paths:
            return code, None, None
        try:
            test_suites = [
                test_suite
                for report_path in report_paths
                for test_suite in ET.parse(report_path).findall(".//testsuite")
            ]
            tests = sum(int(test_suite.attrib["tests"]) for test_suite in test_suites)
            skipped = sum(int(test_suite.attrib["skipped"]) for test_suite in test_suites)
        except (ET.ParseError, KeyError, OSError, TypeError, ValueError):
            return code, None, None
        return code, tests, skipped


def validated_test_count(
    shard_index: int,
    group: list[TestSelection],
    counts: dict[str, int],
    tests: int | None,
    skipped: int | None,
) -> int | None:
    suite_names = ", ".join(selection.name for selection in group)
    expected = sum(counts[selection.name] for selection in group)
    if tests is None or skipped is None:
        print(f"::error::Shard {shard_index} did not produce parseable xUnit test counts ({suite_names})", flush=True)
        return None
    if tests + skipped != expected:
        print(
            f"::error::Shard {shard_index} executed {tests} tests, expected {expected} ({suite_names})",
            flush=True,
        )
        return None
    # Return the accounted total (executed + skipped), not just executed, so the
    # whole-run assertion in main() stays consistent with this per-shard check.
    # Otherwise a single `.disabled` test passes every shard and then trips the
    # final total with a misleading message.
    return tests + skipped


def main() -> int:
    args = parse_args()
    if args.group_size < 1:
        print("--group-size must be positive", file=sys.stderr)
        return 2

    swift_command = [args.swift_command, *args.swift_command_arg]
    suites, counts = swift_test_list(swift_command)
    suite_groups = list(chunks(suites, args.group_size))
    try:
        suite_groups = shard_groups(suite_groups, args.shard_index, args.shard_count)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2
    if args.limit_groups is not None:
        suite_groups = suite_groups[: args.limit_groups]

    shard_suffix = ""
    if args.shard_index is not None and args.shard_count is not None:
        shard_suffix = f" in shard {args.shard_index + 1}/{args.shard_count}"
    print(f"Discovered {len(suites)} test selections; running {len(suite_groups)} groups{shard_suffix}", flush=True)
    if args.list_only:
        for group in suite_groups:
            for suite in group:
                print(suite.name)
        return 0

    if not suite_groups:
        print("No test groups selected.", flush=True)
        return 0

    accounted_total = 0
    for group_index, group in enumerate(suite_groups, start=1):
        expected = sum(counts[selection.name] for selection in group)
        print(
            f"::group::Swift test shard {group_index}/{len(suite_groups)} "
            f"({len(group)} selections, {expected} expected tests)",
            flush=True,
        )
        result, tests, skipped = run_group(group, args.timeout, swift_command)
        print("::endgroup::", flush=True)
        if result == 0:
            accounted = validated_test_count(group_index, group, counts, tests, skipped)
            if accounted is None:
                return 1
            accounted_total += accounted
            continue
        if len(group) == 1:
            return result

        if result != 124:
            print(f"Shard {group_index} failed with exit code {result}; retrying shard once", flush=True)
            retry_result, retry_tests, retry_skipped = run_group(group, args.timeout, swift_command)
            if retry_result == 0:
                accounted = validated_test_count(group_index, group, counts, retry_tests, retry_skipped)
                if accounted is None:
                    return 1
                accounted_total += accounted
                continue
            return retry_result

        print(f"Shard {group_index} timed out; retrying suites one at a time", flush=True)
        for suite in group:
            print(f"::group::Swift test retry {suite.name}", flush=True)
            retry_result, retry_tests, retry_skipped = run_group([suite], args.timeout, swift_command)
            print("::endgroup::", flush=True)
            if retry_result != 0:
                return retry_result
            accounted = validated_test_count(group_index, [suite], counts, retry_tests, retry_skipped)
            if accounted is None:
                return 1
            accounted_total += accounted

    print(f"Accounted for {accounted_total} discovered tests across {len(suite_groups)} groups", flush=True)
    if args.shard_index is None and args.shard_count is None and args.limit_groups is None:
        expected_total = sum(counts.values())
        if accounted_total != expected_total:
            print(f"::error::Accounted for {accounted_total} tests, expected {expected_total} across the full run", flush=True)
            return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
