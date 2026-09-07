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
                           runTimes: seq[float] = @[],
                           runMems: seq[float] = @[]): Benchmark =
  result = initBenchmark(name, times.len, 0)
  result.times = times
  result.mems = memories
  finalize(result)

  if runTimes.len > 0:
    result.runTimes = runTimes
  if runMems.len > 0:
    result.runMems = runMems

  result.params.runs = min(result.runTimes.len, result.runMems.len)


proc newSyntheticSuite(benchmark: Benchmark): BenchmarkSuite =
  result = initSuite("Synthetic")
  result.add(benchmark)


suite "Benchmark comparisons should":
  test "preserve samples and process runs in CSV summaries":
    let path =
      getTempDir() / ("vecs-benchmarks-" & $getCurrentProcessId() & ".csv")
    defer:
      if fileExists(path):
        removeFile(path)

    let benchmark = newSyntheticBenchmark(
      "sample",
      @[1.0, 2.0, 3.0, 4.0],
      @[10.0, 20.0, 30.0, 40.0],
      @[2.0, 2.5, 3.0],
      @[20.0, 25.0, 30.0]
    )
    let suite = newSyntheticSuite(benchmark)

    suite.saveSummary(path)
    let loaded = loadBenchmarkSuiteFromCsv(path)

    check loaded.benchmarks.len == 1
    check loaded.benchmarks[0].times == benchmark.times
    check loaded.benchmarks[0].mems == benchmark.mems
    check loaded.benchmarks[0].runTimes == benchmark.runTimes
    check loaded.benchmarks[0].runMems == benchmark.runMems


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


  test "ignore raw sample volume when process runs disagree":
    let baseline = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(100.0, 100),
        repeatedValues(100.0, 100),
        repeatedValues(100.0, MinimumComparisonRuns),
        repeatedValues(100.0, MinimumComparisonRuns)
      )
    )
    let candidate = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(80.0, 100),
        repeatedValues(80.0, 100),
        @[
          95.0, 105.0, 95.0, 105.0, 95.0,
          105.0, 95.0, 105.0, 95.0, 105.0,
          95.0, 105.0, 95.0, 105.0, 95.0
        ],
        @[
          95.0, 105.0, 95.0, 105.0, 95.0,
          105.0, 95.0, 105.0, 95.0, 105.0,
          95.0, 105.0, 95.0, 105.0, 95.0
        ]
      )
    )

    let comparison =
      compareBenchmarkSuites(baseline, candidate, "synthetic.csv")

    check comparison.results[0].timeStatus == ChangeInconclusive
    check comparison.results[0].memStatus == ChangeInconclusive


  test "require enough independent process runs":
    let baseline = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(100.0, 100),
        repeatedValues(100.0, 100),
        repeatedValues(100.0, MinimumComparisonRuns - 1),
        repeatedValues(100.0, MinimumComparisonRuns - 1)
      )
    )
    let candidate = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(80.0, 100),
        repeatedValues(80.0, 100),
        repeatedValues(80.0, MinimumComparisonRuns - 1),
        repeatedValues(80.0, MinimumComparisonRuns - 1)
      )
    )

    let comparison =
      compareBenchmarkSuites(baseline, candidate, "synthetic.csv")

    check comparison.results[0].timeStatus == ChangeInconclusive
    check comparison.results[0].memStatus == ChangeInconclusive


  test "detect an improvement across process runs":
    let baselineRuns = repeatedValues(100.0, MinimumComparisonRuns)
    var candidateRuns = repeatedValues(80.0, MinimumComparisonRuns)
    candidateRuns[^1] = 105.0

    let baseline = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(100.0, 100),
        repeatedValues(100.0, 100),
        baselineRuns,
        baselineRuns
      )
    )
    let candidate = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(80.0, 100),
        repeatedValues(80.0, 100),
        candidateRuns,
        candidateRuns
      )
    )

    let comparison =
      compareBenchmarkSuites(baseline, candidate, "synthetic.csv")

    check comparison.results[0].timeStatus == ChangeImproved
    check comparison.results[0].memStatus == ChangeImproved


  test "treat sub-percent process changes as unchanged":
    let baseline = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(100.0, 100),
        repeatedValues(100.0, 100),
        repeatedValues(100.0, MinimumComparisonRuns),
        repeatedValues(100.0, MinimumComparisonRuns)
      )
    )
    let candidate = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(100.5, 100),
        repeatedValues(100.5, 100),
        repeatedValues(100.5, MinimumComparisonRuns),
        repeatedValues(100.5, MinimumComparisonRuns)
      )
    )

    let comparison =
      compareBenchmarkSuites(baseline, candidate, "synthetic.csv")

    check comparison.results[0].timeStatus == ChangeUnchanged
    check comparison.results[0].memStatus == ChangeUnchanged


  test "leave overlapping process measurements inconclusive":
    let baseline = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(100.0, 100),
        repeatedValues(100.0, 100),
        repeatedValues(100.0, MinimumComparisonRuns),
        repeatedValues(100.0, MinimumComparisonRuns)
      )
    )
    let candidate = newSyntheticSuite(
      newSyntheticBenchmark(
        "sample",
        repeatedValues(105.0, 100),
        repeatedValues(100.0, 100),
        @[
          95.0, 105.0, 95.0, 105.0, 95.0,
          105.0, 95.0, 105.0, 95.0, 105.0,
          95.0, 105.0, 95.0, 105.0, 95.0
        ],
        repeatedValues(100.0, MinimumComparisonRuns)
      )
    )

    let comparison =
      compareBenchmarkSuites(baseline, candidate, "synthetic.csv")

    check comparison.results[0].timeStatus == ChangeInconclusive
    check comparison.results[0].memStatus == ChangeUnchanged
