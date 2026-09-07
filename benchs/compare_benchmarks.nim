# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import os
import helpers/benchmarks


proc loadMerged(paths: seq[string]): BenchmarkSuite =
  for path in paths:
    result.merge(loadBenchmarkSuiteFromCsv(path))


proc splitPaths(arguments: seq[string],
                candidatePaths, baselinePaths: var seq[string]): bool =
  var foundSeparator = false

  for argument in arguments:
    if argument == "--":
      if foundSeparator:
        return false
      foundSeparator = true
    elif foundSeparator:
      baselinePaths.add argument
    else:
      candidatePaths.add argument

  if not foundSeparator and arguments.len == 4:
    candidatePaths = arguments[0 .. 1]
    baselinePaths = arguments[2 .. 3]
    return true

  result =
    foundSeparator and
    candidatePaths.len > 0 and
    candidatePaths.len == baselinePaths.len


proc describeRuns(paths: seq[string]): string =
  result = paths[0]
  if paths.len > 1:
    result.add " + " & $(paths.len - 1) & " more runs"


proc usage(): string =
  result =
    "usage: compare_benchmarks <candidate.csv>... -- <baseline.csv>..."


if isMainModule:
  var candidatePaths: seq[string]
  var baselinePaths: seq[string]
  if not splitPaths(commandLineParams(), candidatePaths, baselinePaths):
    quit(usage(), QuitFailure)

  let candidate = loadMerged(candidatePaths)
  let baseline = loadMerged(baselinePaths)
  let baselineName = describeRuns(baselinePaths)

  echo compareBenchmarkSuites(baseline, candidate, baselineName)
