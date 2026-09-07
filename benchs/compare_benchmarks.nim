# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import os
import helpers/benchmarks


proc loadMerged(firstPath, secondPath: string): BenchmarkSuite =
  let first = loadBenchmarkSuiteFromCsv(firstPath)
  let second = loadBenchmarkSuiteFromCsv(secondPath)
  result = mergeBenchmarkSuites([first, second])


proc usage(): string =
  result =
    "usage: compare_benchmarks " &
    "<candidate-a.csv> <candidate-b.csv> " &
    "<baseline-a.csv> <baseline-b.csv>"


if isMainModule:
  if paramCount() != 4:
    quit(usage(), QuitFailure)

  let candidate = loadMerged(paramStr(1), paramStr(2))
  let baseline = loadMerged(paramStr(3), paramStr(4))
  let baselineName = paramStr(3) & " + " & paramStr(4)

  echo compareBenchmarkSuites(baseline, candidate, baselineName)
