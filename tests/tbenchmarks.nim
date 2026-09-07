# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import unittest, os
import ../benchs/helpers/benchmarks


proc repeatedValues(value: float, count: int): seq[float] =
  result = newSeq[float](count)
  for index in 0 ..< count:
    result[index] = value


proc newSyntheticBenchmark(name: string, times, memories: seq[float],
                           runs: int = 1): Benchmark =
  result = initBenchmark(name, times.len, 0)
  result.times = times
  result.mems = memories
  result.params.runs = runs
  finalize(result)


proc newSyntheticSuite(benchmark: Benchmark): BenchmarkSuite =
  result = initSuite("Synthetic")
  result.add(benchmark)


suite "Benchmark comparisons should":
  test "preserve raw samples in CSV summaries":
    let path =
      getTempDir() / ("vecs-benchmarks-" & $getCurrentProcessId() & ".csv")
    defer:
      if fileExists(path):
        removeFile(path)

    let benchmark = newSyntheticBenchmark(
      "sample",
      @[1.0, 2.0, 3.0, 4.0],
      @[10.0, 20.0, 30.0, 40.0]
    )
    let suite = newSyntheticSuite(benchmark)

    suite.saveSummary(path)
    let loaded = loadBenchmarkSuiteFromCsv(path)

    check loaded.benchmarks.len == 1
    check loaded.benchmarks[0].times == benchmark.times
    check loaded.benchmarks[0].mems == benchmark.mems


  test "keep a single-run comparison inconclusive":
    let baseline = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(100.0, 100),
        repeatedValues(100.0, 100)
      )
    )
    let candidate = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(80.0, 100),
        repeatedValues(80.0, 100)
      )
    )

    let comparison =
      compareBenchmarkSuites(baseline, candidate, "synthetic.csv")

    check comparison.results[0].timeStatus == ChangeInconclusive
    check comparison.results[0].memStatus == ChangeInconclusive


  test "detect a repeated improvement":
    let baseline = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(100.0, 100),
        repeatedValues(100.0, 100),
        runs = 2
      )
    )
    let candidate = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(80.0, 100),
        repeatedValues(80.0, 100),
        runs = 2
      )
    )

    let comparison =
      compareBenchmarkSuites(baseline, candidate, "synthetic.csv")

    check comparison.results[0].timeStatus == ChangeImproved
    check comparison.results[0].memStatus == ChangeImproved


  test "treat sub-percent repeated changes as unchanged":
    let baseline = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(100.0, 100),
        repeatedValues(100.0, 100),
        runs = 2
      )
    )
    let candidate = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(100.5, 100),
        repeatedValues(100.5, 100),
        runs = 2
      )
    )

    let comparison =
      compareBenchmarkSuites(baseline, candidate, "synthetic.csv")

    check comparison.results[0].timeStatus == ChangeUnchanged
    check comparison.results[0].memStatus == ChangeUnchanged


  test "leave overlapping repeated measurements inconclusive":
    let baseline = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        @[90.0, 100.0, 110.0, 90.0, 100.0, 110.0],
        repeatedValues(100.0, 6),
        runs = 2
      )
    )
    let candidate = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        @[95.0, 105.0, 115.0, 95.0, 105.0, 115.0],
        repeatedValues(100.0, 6),
        runs = 2
      )
    )

    let comparison =
      compareBenchmarkSuites(baseline, candidate, "synthetic.csv")

    check comparison.results[0].timeStatus == ChangeInconclusive
    check comparison.results[0].memStatus == ChangeUnchanged
