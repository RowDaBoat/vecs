# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import math, algorithm, strutils, tables, std/monotimes, os


const
  MinimumSampleTime = 0.001
  MaximumBatchSize = 10_000


type
  Parameters* = object
    samples*: int
    warmup*: int
    batchSize*: int
    runs*: int
    maxTime*: float
    maxMem*: float

  Statistics* = object
    min*: float
    max*: float
    mean*: float
    median*: float
    stddev*: float
    q1*: float
    q3*: float
    iqr*: float

  Benchmark* = object
    name*: string
    params*: Parameters
    times*: seq[float]
    mems*: seq[float]
    timeStats*: Statistics
    memStats*: Statistics
    totalTime*: float
    totalMem*: float

  BenchmarkSuite* = object
    name*: string
    benchmarks*: seq[Benchmark]

  Comparison* = object
    baseline*: string
    candidate*: string
    timeRatio*: float
    memRatio*: float
    timeImprovement*: float
    memImprovement*: float
    isFaster*: bool
    usesLessMem*: bool


proc prettyTime*(t: float): string =
  var fac = 1.0
  var suffix = "s"

  if t < 1e-6:
    fac = 1e9
    suffix = "ns"
  elif t < 1e-3:
    fac = 1e6
    suffix = "µs"
  elif t < 1:
    fac = 1e3
    suffix = "ms"

  let v = t * fac
  result = v.formatFloat(ffDecimal, 2) & " " & suffix


proc prettyMem*(m: float): string =
  let sign = if m < 0: "-" else: ""
  let a = abs(m)
  if a < 1024:
    return sign & a.formatFloat(ffDecimal, 2) & " B "
  elif a < 1024 * 1024:
    return sign & (a / 1024).formatFloat(ffDecimal, 2) & " KB"
  else:
    return sign & (a / (1024 * 1024)).formatFloat(ffDecimal, 2) & " MB"


proc prettyPercent*(p: float): string =
  let sign = if p >= 0: "+" else: ""
  return sign & (p * 100).formatFloat(ffDecimal, 1) & "%"


proc calculateStatistics*(values: seq[float]): Statistics =
  if values.len == 0:
    return

  var sorted = values
  sorted.sort()

  result.min = sorted[0]
  result.max = sorted[^1]

  var sum = 0.0
  var variance = 0.0
  for v in sorted:
    sum += v

  result.mean = sum / sorted.len.float

  for v in sorted:
    let diff = v - result.mean
    variance += diff * diff

  if sorted.len > 1:
    result.stddev = sqrt(variance / (sorted.len - 1).float)

  let mid = sorted.len div 2
  if sorted.len mod 2 == 0:
    result.median = (sorted[mid - 1] + sorted[mid]) / 2.0
  else:
    result.median = sorted[mid]

  let q1Idx = sorted.len div 4
  let q3Idx = (3 * sorted.len) div 4
  result.q1 = sorted[q1Idx]
  result.q3 = sorted[q3Idx]
  result.iqr = result.q3 - result.q1


proc finalize*(b: var Benchmark) =
  b.timeStats = calculateStatistics(b.times)
  b.memStats = calculateStatistics(b.mems)

  b.totalTime = 0.0
  for t in b.times:
    b.totalTime += t

  b.totalMem = 0.0
  for m in b.mems:
    b.totalMem += m


proc showSummary*(b: Benchmark) =
  echo "╭─ ", b.name, " (", b.params.samples, " samples)"
  echo "├─ Time  : ", prettyTime(b.timeStats.median),
       " (min: ", prettyTime(b.timeStats.min),
       ", max: ", prettyTime(b.timeStats.max), ")"
  echo "├─ Memory: ", prettyMem(b.memStats.median),
       " (min: ", prettyMem(b.memStats.min),
       ", max: ", prettyMem(b.memStats.max), ")"
  echo "╰─ Stddev: ±", prettyTime(b.timeStats.stddev)


proc showDetailed*(b: Benchmark) =
  echo "=".repeat(70)
  echo "Benchmark: ", b.name
  echo "Samples: ", b.params.samples,
       " (warmup: ", b.params.warmup,
       ", batch: ", b.params.batchSize, ")"
  echo ""

  echo "Time Statistics:"
  echo "  Min     : ", prettyTime(b.timeStats.min)
  echo "  Q1      : ", prettyTime(b.timeStats.q1)
  echo "  Median  : ", prettyTime(b.timeStats.median)
  echo "  Mean    : ", prettyTime(b.timeStats.mean)
  echo "  Q3      : ", prettyTime(b.timeStats.q3)
  echo "  Max     : ", prettyTime(b.timeStats.max)
  echo "  Stddev  : ±", prettyTime(b.timeStats.stddev)
  echo "  IQR     : ", prettyTime(b.timeStats.iqr)
  echo ""

  echo "Memory Statistics:"
  echo "  Min     : ", prettyMem(b.memStats.min)
  echo "  Median  : ", prettyMem(b.memStats.median)
  echo "  Mean    : ", prettyMem(b.memStats.mean)
  echo "  Max     : ", prettyMem(b.memStats.max)
  echo "  Stddev  : ±", prettyMem(b.memStats.stddev)
  echo "=".repeat(70)


proc notNaN(v: float): float =
  if v.isNaN or v.classify in {fcInf, fcNegInf}:
    return 0.0

  return v


proc compare*(baseline, candidate: Benchmark): Comparison =
  result.baseline = baseline.name
  result.candidate = candidate.name

  result.timeRatio = notNaN(candidate.timeStats.median / baseline.timeStats.median)
  result.memRatio = notNaN(candidate.memStats.median / baseline.memStats.median)

  result.timeImprovement = notNaN((baseline.timeStats.median - candidate.timeStats.median) / baseline.timeStats.median)
  result.memImprovement = notNaN((baseline.memStats.median - candidate.memStats.median) / baseline.memStats.median)

  result.isFaster = result.timeImprovement > 0
  result.usesLessMem = result.memImprovement > 0


proc showComparison*(cmp: Comparison) =
  echo ""
  echo "╔═", "═".repeat(66), "═╗"
  echo "║ ", "Comparison: ", cmp.baseline, " vs ", cmp.candidate, " ".repeat(max(0, 66 - 14 - cmp.baseline.len - cmp.candidate.len - 4)), "║"
  echo "╠═", "═".repeat(66), "═╣"

  let timeIcon = if cmp.isFaster: "✓" else: "✗"
  echo "║ Time   : ", timeIcon, " ",
       (if cmp.isFaster: "FASTER" else: "SLOWER"), " by ",
       prettyPercent(abs(cmp.timeImprovement)),
       " (", cmp.timeRatio.formatFloat(ffDecimal, 2), "x)",
       " ".repeat(max(0, 48 - (if cmp.isFaster: 7 else: 6) - prettyPercent(abs(cmp.timeImprovement)).len - 3 - cmp.timeRatio.formatFloat(ffDecimal, 2).len)), "║"

  let memIcon = if cmp.usesLessMem: "✓" else: "✗"
  echo "║ Memory : ", memIcon, " ",
       (if cmp.usesLessMem: "LESS" else: "MORE"), " by ",
       prettyPercent(abs(cmp.memImprovement)),
       " (", cmp.memRatio.formatFloat(ffDecimal, 2), "x)",
       " ".repeat(max(0, 51 - (if cmp.usesLessMem: 4 else: 4) - prettyPercent(abs(cmp.memImprovement)).len - 3 - cmp.memRatio.formatFloat(ffDecimal, 2).len)), "║"

  echo "╚═", "═".repeat(66), "═╝"


var blackHole* {.volatile.}: uint64


proc blackBox*[T](value: T) {.noinline.} =
  ## Keeps `value` observable so the optimiser cannot delete the work that
  ## produced it. Under `-d:danger` a loop whose result is never read is dead code.
  ##
  ## Call this once per benchmark, after the sampling loop. The accumulator is
  ## then live across the whole benchmark, so the loop cannot be removed and no
  ## cost lands inside the timed region.
  var local = value
  let bytes = cast[ptr UncheckedArray[byte]](addr local)
  var acc = blackHole
  for i in 0 ..< sizeof(T):
    acc = acc xor (bytes[i].uint64 shl ((i and 7) * 8))
  blackHole = acc


proc initBenchmark*(benchmarkName: string, sample, warm: int): Benchmark =
  result.name = benchmarkName
  result.params =
    Parameters(samples: sample, warmup: warm, batchSize: 1, runs: 1)
  result.times = newSeqOfCap[float](sample)
  result.mems = newSeqOfCap[float](sample)


template measure*(bench: var Benchmark, memBaseline: int, code: untyped) =
  let t0 = getMonoTime()
  code
  let elapsed = (getMonoTime() - t0).inNanoseconds.float / 1e9

  bench.times.add(elapsed)
  bench.mems.add((getOccupiedMem() - memBaseline).float)


proc batchSizeFor(elapsed: float, target: float): int =
  if elapsed <= 0.0:
    return 1

  result = ceil(target / elapsed).int
  result = clamp(result, 1, MaximumBatchSize)


template measureRepeated(bench: var Benchmark, memBaseline, repetitions: int,
                         code: untyped) =
  let t0 = getMonoTime()
  for repetitionIndex in 0 ..< repetitions:
    code
  let elapsed = (getMonoTime() - t0).inNanoseconds.float / 1e9

  bench.times.add(elapsed / repetitions.float)
  bench.mems.add((getOccupiedMem() - memBaseline).float)


template benchmark*(benchmarkName: string, sample, code: untyped): untyped =
  benchmark(benchmarkName, sample, 1, code)


template benchmark*(benchmarkName: string, sample, warm, code: untyped): untyped =
  var bench = initBenchmark(benchmarkName, sample, warm)

  block:
    for i in 0 ..< warm:
      code

    for i in 0 ..< sample:
      let memBaseline = getOccupiedMem()
      measure(bench, memBaseline):
        code

  finalize(bench)
  bench


template benchmarkWithSetup*(benchmarkName: string, sample, setup, code: untyped): untyped =
  benchmarkWithSetup(benchmarkName, sample, 1, setup, code)


template benchmarkWithSetup*(benchmarkName: string, sample, warm, setup, code: untyped): untyped =
  var bench = initBenchmark(benchmarkName, sample, warm)

  block:
    for i in 0 ..< warm:
      setup
      code

    for i in 0 ..< sample:
      let memBaseline = getOccupiedMem()
      setup
      measure(bench, memBaseline):
        code

  finalize(bench)
  bench


template benchmarkRepeatedWithSetup*(benchmarkName: string, sample, warm,
                                      setup, code: untyped): untyped =
  var bench = initBenchmark(benchmarkName, sample, warm)

  block:
    var repetitions = 1
    block:
      setup
      let calibrationStart = getMonoTime()
      code
      let calibrationTime =
        (getMonoTime() - calibrationStart).inNanoseconds.float / 1e9
      repetitions = batchSizeFor(calibrationTime, MinimumSampleTime)

    bench.params.batchSize = repetitions

    for warmupIndex in 0 ..< warm:
      setup
      for repetitionIndex in 0 ..< repetitions:
        code

    for sampleIndex in 0 ..< sample:
      let memBaseline = getOccupiedMem()
      setup
      measureRepeated(bench, memBaseline, repetitions):
        code

  finalize(bench)
  bench


proc initSuite*(name: string): BenchmarkSuite =
  result.name = name
  result.benchmarks = @[]


proc add*(suite: var BenchmarkSuite, bench: Benchmark) =
  suite.benchmarks.add(bench)


proc showSummary*(suite: BenchmarkSuite) =
  echo ""
  echo "╔═", "═".repeat(60), "═╗"
  echo "║ ", suite.name, " Operations", " ".repeat(max(0, 50 - suite.name.len)), "║"
  echo "╠═", "═".repeat(60), "═╣"

  for bench in suite.benchmarks:
    let timeStr = prettyTime(bench.timeStats.median).alignLeft(12)
    let memStr = prettyMem(bench.memStats.median).alignLeft(12)
    let nameStr = bench.name.alignLeft(30)
    echo "║ ", nameStr, " │ ", timeStr, " │ ", memStr, " ║"

  echo "╚═", "═".repeat(60), "═╝"


const
  DefaultComparisonConfidence* = 0.999
  DefaultMinimumRelativeChange* = 0.01


proc serializeSamples(values: seq[float]): string =
  var serialized = newSeq[string](values.len)
  for index, value in values:
    serialized[index] = value.formatFloat(ffScientific, 10)

  result = serialized.join(";")


proc saveSummary*(suite: BenchmarkSuite, path: string) =
  var file = open(path, fmWrite)
  defer: file.close()

  file.writeLine(
    suite.name &
    ",time_median,mem_median,time_seconds,mem_bytes,time_samples,mem_samples,batch_size"
  )

  for bench in suite.benchmarks:
    let memory = prettyMem(bench.memStats.median)
    let time = prettyTime(bench.timeStats.median)
    file.writeLine(
      bench.name & "," & time & "," & memory & "," &
      bench.timeStats.median.formatFloat(ffScientific, 10) & "," &
      bench.memStats.median.formatFloat(ffScientific, 10) & "," &
      serializeSamples(bench.times) & "," &
      serializeSamples(bench.mems) & "," &
      $bench.params.batchSize
    )


type
  ConfidenceInterval* = object
    lower*: float
    upper*: float

  ChangeStatus* = enum
    ChangeUnchanged
    ChangeInconclusive
    ChangeImproved
    ChangeRegressed

  MetricComparison = object
    ratio: float
    change: float
    changeInterval: ConfidenceInterval
    difference: float
    status: ChangeStatus
    hasRelativeChange: bool

  BenchResult* = object
    name*: string
    timeRatio*: float
    memRatio*: float
    timeImprovement*: float
    memImprovement*: float
    timeChangeInterval*: ConfidenceInterval
    memChangeInterval*: ConfidenceInterval
    timeDifference*: float
    memDifference*: float
    timeStatus*: ChangeStatus
    memStatus*: ChangeStatus
    timeSignificant*: bool
    memSignificant*: bool
    timeBetter*: bool
    memBetter*: bool
    timeHasRelativeChange*: bool
    memHasRelativeChange*: bool
    missingInBaseline*: bool

  BenchComp* = object
    suiteName*: string
    baselineFile*: string
    margin*: float
    confidence*: float
    minimumRelativeChange*: float
    baselineRuns*: int
    candidateRuns*: int
    results*: seq[BenchResult]
    missingInCurrent*: seq[string]


proc parseNumber(value: string, number: var float): bool =
  try:
    number = parseFloat(value)
    result = true
  except ValueError:
    result = false


proc parseSamples(value: string): seq[float] =
  for serialized in value.split(';'):
    var number = 0.0
    if parseNumber(serialized, number):
      result.add(number)


proc parseBatchSize(value: string): int =
  try:
    result = max(1, parseInt(value))
  except ValueError:
    result = 1


proc benchmarkFromCsv(parts: seq[string], benchmark: var Benchmark): bool =
  if parts.len < 5:
    return false

  var medianTime = 0.0
  var medianMemory = 0.0
  if not parseNumber(parts[3], medianTime):
    return false
  if not parseNumber(parts[4], medianMemory):
    return false

  benchmark = initBenchmark(parts[0], 1, 0)
  if parts.len >= 7:
    benchmark.times = parseSamples(parts[5])
    benchmark.mems = parseSamples(parts[6])

  if benchmark.times.len == 0:
    benchmark.times.add(medianTime)
  if benchmark.mems.len == 0:
    benchmark.mems.add(medianMemory)
  if parts.len >= 8:
    benchmark.params.batchSize = parseBatchSize(parts[7])

  benchmark.params.samples = benchmark.times.len
  finalize(benchmark)
  result = true


proc loadBenchmarkSuiteFromCsv*(path: string): BenchmarkSuite =
  result.benchmarks = @[]
  if not fileExists(path):
    return

  var file = open(path, fmRead)
  defer: file.close()

  var isHeader = true
  for line in file.lines:
    if isHeader:
      let headerParts = line.split(',', 1)
      result.name = if headerParts.len > 0: headerParts[0] else: "Baseline"
      isHeader = false
    else:
      var benchmark: Benchmark
      if benchmarkFromCsv(line.split(','), benchmark):
        result.benchmarks.add(benchmark)


proc benchmarkIndex(suite: BenchmarkSuite, benchmarkName: string): int =
  for index, benchmark in suite.benchmarks:
    if benchmark.name == benchmarkName:
      return index

  result = -1


proc merge*(suite: var BenchmarkSuite, addition: BenchmarkSuite) =
  if suite.name.len == 0:
    suite.name = addition.name

  for addedBenchmark in addition.benchmarks:
    let index = suite.benchmarkIndex(addedBenchmark.name)
    if index < 0:
      suite.benchmarks.add(addedBenchmark)
    else:
      suite.benchmarks[index].times.add(addedBenchmark.times)
      suite.benchmarks[index].mems.add(addedBenchmark.mems)
      suite.benchmarks[index].params.samples = suite.benchmarks[index].times.len
      suite.benchmarks[index].params.runs += addedBenchmark.params.runs
      suite.benchmarks[index].params.batchSize =
        max(suite.benchmarks[index].params.batchSize,
            addedBenchmark.params.batchSize)
      finalize(suite.benchmarks[index])


proc mergeBenchmarkSuites*(suites: openArray[BenchmarkSuite]): BenchmarkSuite =
  for suite in suites:
    result.merge(suite)


proc lowerConfidenceIndex(sampleCount: int, tailProbability: float): int =
  if sampleCount <= 1:
    return 0

  let centerIndex = sampleCount div 2
  let centerProbability = exp(
    lgamma((sampleCount + 1).float) -
    lgamma((centerIndex + 1).float) -
    lgamma((sampleCount - centerIndex + 1).float) -
    sampleCount.float * ln(2.0)
  )

  var probabilities = newSeq[float](centerIndex + 1)
  probabilities[centerIndex] = centerProbability
  for index in countdown(centerIndex, 1):
    let numerator = index.float
    let denominator = (sampleCount - index + 1).float
    probabilities[index - 1] =
      probabilities[index] * numerator / denominator

  var cumulativeProbability = 0.0
  for index in 0 ..< centerIndex:
    cumulativeProbability += probabilities[index]
    if cumulativeProbability <= tailProbability:
      result = index
    else:
      return


proc medianConfidenceInterval*(values: seq[float],
                               confidence: float): ConfidenceInterval =
  if values.len == 0:
    return

  var sorted = values
  sorted.sort()

  let tailProbability = (1.0 - confidence) / 2.0
  let lowerIndex = lowerConfidenceIndex(sorted.len, tailProbability)
  let upperIndex = sorted.high - lowerIndex

  result.lower = sorted[lowerIndex]
  result.upper = sorted[upperIndex]


proc classifyRelativeChange(interval: ConfidenceInterval,
                            hasRepeatedRuns: bool,
                            minimumRelativeChange: float): ChangeStatus =
  if interval.lower == 0.0 and interval.upper == 0.0:
    return ChangeUnchanged
  if not hasRepeatedRuns:
    return ChangeInconclusive
  if interval.upper < -minimumRelativeChange:
    return ChangeImproved
  if interval.lower > minimumRelativeChange:
    return ChangeRegressed
  if interval.lower >= -minimumRelativeChange and
      interval.upper <= minimumRelativeChange:
    return ChangeUnchanged

  result = ChangeInconclusive


proc classifyAbsoluteChange(interval: ConfidenceInterval,
                            hasRepeatedRuns: bool): ChangeStatus =
  if interval.lower == 0.0 and interval.upper == 0.0:
    return ChangeUnchanged
  if not hasRepeatedRuns:
    return ChangeInconclusive
  if interval.upper < 0.0:
    return ChangeImproved
  if interval.lower > 0.0:
    return ChangeRegressed

  result = ChangeInconclusive


proc compareMetric(baselineValues, candidateValues: seq[float],
                   baselineRuns, candidateRuns: int,
                   confidence,
                   minimumRelativeChange: float): MetricComparison =
  if baselineValues.len == 0 or candidateValues.len == 0:
    result.status = ChangeInconclusive
    return

  let medianConfidence = 1.0 - (1.0 - confidence) / 2.0
  let baselineInterval =
    medianConfidenceInterval(baselineValues, medianConfidence)
  let candidateInterval =
    medianConfidenceInterval(candidateValues, medianConfidence)
  let baselineMedian = calculateStatistics(baselineValues).median
  let candidateMedian = calculateStatistics(candidateValues).median

  let differenceInterval = ConfidenceInterval(
    lower: candidateInterval.lower - baselineInterval.upper,
    upper: candidateInterval.upper - baselineInterval.lower
  )
  let hasRepeatedRuns = baselineRuns >= 2 and candidateRuns >= 2

  result.difference = candidateMedian - baselineMedian

  if baselineMedian == 0.0 or baselineInterval.lower <= 0.0:
    result.status = classifyAbsoluteChange(
      differenceInterval,
      hasRepeatedRuns
    )
    return

  result.hasRelativeChange = true
  result.ratio = candidateMedian / baselineMedian
  result.change = result.ratio - 1.0
  result.changeInterval = ConfidenceInterval(
    lower: candidateInterval.lower / baselineInterval.upper - 1.0,
    upper: candidateInterval.upper / baselineInterval.lower - 1.0
  )
  result.status = classifyRelativeChange(
    result.changeInterval,
    hasRepeatedRuns,
    minimumRelativeChange
  )


proc benchmarkResult(baseline, candidate: Benchmark,
                     confidence,
                     minimumRelativeChange: float): BenchResult =
  result.name = candidate.name

  let timeComparison = compareMetric(
    baseline.times,
    candidate.times,
    baseline.params.runs,
    candidate.params.runs,
    confidence,
    minimumRelativeChange
  )
  let memoryComparison = compareMetric(
    baseline.mems,
    candidate.mems,
    baseline.params.runs,
    candidate.params.runs,
    confidence,
    minimumRelativeChange
  )

  result.timeRatio = timeComparison.ratio
  result.timeImprovement = timeComparison.change
  result.timeChangeInterval = timeComparison.changeInterval
  result.timeDifference = timeComparison.difference
  result.timeStatus = timeComparison.status
  result.timeSignificant =
    timeComparison.status in {ChangeImproved, ChangeRegressed}
  result.timeBetter = timeComparison.status == ChangeImproved
  result.timeHasRelativeChange = timeComparison.hasRelativeChange

  result.memRatio = memoryComparison.ratio
  result.memImprovement = memoryComparison.change
  result.memChangeInterval = memoryComparison.changeInterval
  result.memDifference = memoryComparison.difference
  result.memStatus = memoryComparison.status
  result.memSignificant =
    memoryComparison.status in {ChangeImproved, ChangeRegressed}
  result.memBetter = memoryComparison.status == ChangeImproved
  result.memHasRelativeChange = memoryComparison.hasRelativeChange


proc suiteRuns(suite: BenchmarkSuite): int =
  if suite.benchmarks.len == 0:
    return 0

  result = suite.benchmarks[0].params.runs


proc compareBenchmarkSuites*(baseline, candidate: BenchmarkSuite,
                             baselineName: string,
                             confidence: float =
                               DefaultComparisonConfidence,
                             minimumRelativeChange: float =
                               DefaultMinimumRelativeChange): BenchComp =
  result.suiteName = candidate.name
  result.baselineFile = baselineName
  result.margin = minimumRelativeChange
  result.confidence = confidence
  result.minimumRelativeChange = minimumRelativeChange
  result.baselineRuns = suiteRuns(baseline)
  result.candidateRuns = suiteRuns(candidate)
  result.results = @[]
  result.missingInCurrent = @[]

  var baselineMap = initTable[string, Benchmark]()
  for benchmark in baseline.benchmarks:
    baselineMap[benchmark.name] = benchmark

  var candidateNames = initTable[string, bool]()
  for candidateBenchmark in candidate.benchmarks:
    candidateNames[candidateBenchmark.name] = true
    if baselineMap.hasKey(candidateBenchmark.name):
      let baselineBenchmark = baselineMap[candidateBenchmark.name]
      result.results.add(
        benchmarkResult(
          baselineBenchmark,
          candidateBenchmark,
          confidence,
          minimumRelativeChange
        )
      )
    else:
      result.results.add(
        BenchResult(
          name: candidateBenchmark.name,
          missingInBaseline: true
        )
      )

  for benchmarkName, baselineBenchmark in baselineMap:
    if not candidateNames.hasKey(benchmarkName):
      result.missingInCurrent.add(baselineBenchmark.name)


proc compareWithBaseline*(suite: BenchmarkSuite,
                          csvPath: string): BenchComp =
  let baseline = loadBenchmarkSuiteFromCsv(csvPath)
  result = compareBenchmarkSuites(
    baseline,
    suite,
    csvPath,
    DefaultComparisonConfidence,
    DefaultMinimumRelativeChange
  )


proc compareWithBaseline*(suite: BenchmarkSuite, csvPath: string,
                          margin: float): BenchComp =
  let baseline = loadBenchmarkSuiteFromCsv(csvPath)
  result = compareBenchmarkSuites(
    baseline,
    suite,
    csvPath,
    DefaultComparisonConfidence,
    margin
  )


proc changeMarker(status: ChangeStatus): string =
  case status
  of ChangeImproved:
    result = "▼"
  of ChangeRegressed:
    result = "▲"
  of ChangeUnchanged:
    result = "="
  of ChangeInconclusive:
    result = "?"


proc timeChangeText(benchmark: BenchResult): string =
  if benchmark.missingInBaseline:
    return "N/A"
  if benchmark.timeHasRelativeChange:
    return changeMarker(benchmark.timeStatus) & " " &
      prettyPercent(benchmark.timeImprovement)

  result = changeMarker(benchmark.timeStatus) & " " &
    prettyTime(benchmark.timeDifference)


proc memoryChangeText(benchmark: BenchResult): string =
  if benchmark.missingInBaseline:
    return "N/A"
  if benchmark.memHasRelativeChange:
    return changeMarker(benchmark.memStatus) & " " &
      prettyPercent(benchmark.memImprovement)

  result = changeMarker(benchmark.memStatus) & " " &
    prettyMem(benchmark.memDifference)


proc comparisonStatus(benchmark: BenchResult): string =
  if benchmark.missingInBaseline:
    return "NEW (no baseline)"

  var statusParts: seq[string] = @[]
  if benchmark.timeStatus == ChangeImproved:
    statusParts.add("FASTER")
  elif benchmark.timeStatus == ChangeRegressed:
    statusParts.add("SLOWER")

  if benchmark.memStatus == ChangeImproved:
    statusParts.add("LESS MEM")
  elif benchmark.memStatus == ChangeRegressed:
    statusParts.add("MORE MEM")

  if statusParts.len > 0:
    return statusParts.join(" + ")
  if benchmark.timeStatus == ChangeUnchanged and
      benchmark.memStatus == ChangeUnchanged:
    return "unchanged"

  result = "inconclusive"


proc `$`*(comparison: BenchComp): string =
  var lines: seq[string] = @[]

  let nameWidth = 30
  let metricWidth = 12
  let statusWidth = 24
  let innerWidth =
    nameWidth + metricWidth + metricWidth + statusWidth + 9
  let confidenceText =
    (comparison.confidence * 100.0).formatFloat(ffDecimal, 1) &
    "% median intervals"
  let minimumEffectText =
    "Minimum directional effect: " &
    (comparison.minimumRelativeChange * 100.0).formatFloat(ffDecimal, 1) &
    "%"
  let runsText =
    "Runs: baseline " & $comparison.baselineRuns &
    ", candidate " & $comparison.candidateRuns

  lines.add ""
  lines.add "╔═" & "═".repeat(innerWidth) & "═╗"
  lines.add "║ " &
    ("Benchmark Comparison: " & comparison.suiteName).alignLeft(innerWidth) &
    " ║"
  lines.add "║ " &
    ("Baseline: " & comparison.baselineFile).alignLeft(innerWidth) &
    " ║"
  lines.add "║ " &
    ("Confidence: " & confidenceText).alignLeft(innerWidth) &
    " ║"
  lines.add "║ " & minimumEffectText.alignLeft(innerWidth) & " ║"
  lines.add "║ " & runsText.alignLeft(innerWidth) & " ║"
  lines.add "╠═" & "═".repeat(nameWidth) &
    "═╪" & "═".repeat(metricWidth) &
    "═╪" & "═".repeat(metricWidth) &
    "═╪" & "═".repeat(statusWidth) & "═╣"
  lines.add "║ " & "Benchmark".alignLeft(nameWidth) &
    " │ " & "Time".alignLeft(metricWidth - 1) &
    " │ " & "Memory".alignLeft(metricWidth - 1) &
    " │ " & "Status".alignLeft(statusWidth - 1) & " ║"
  lines.add "╠═" & "═".repeat(nameWidth) &
    "═╪" & "═".repeat(metricWidth) &
    "═╪" & "═".repeat(metricWidth) &
    "═╪" & "═".repeat(statusWidth) & "═╣"

  for benchmark in comparison.results:
    let benchmarkName =
      (if benchmark.missingInBaseline:
        benchmark.name & "*"
       else:
        benchmark.name)
      .alignLeft(nameWidth)
    let timeText = timeChangeText(benchmark).alignLeft(metricWidth - 1)
    let memoryText = memoryChangeText(benchmark).alignLeft(metricWidth - 1)
    let status = comparisonStatus(benchmark).alignLeft(statusWidth - 1)

    lines.add "║ " & benchmarkName &
      " │ " & timeText &
      " │ " & memoryText &
      " │ " & status & " ║"

  lines.add "╚═" & "═".repeat(nameWidth) &
    "═╧" & "═".repeat(metricWidth) &
    "═╧" & "═".repeat(metricWidth) &
    "═╧" & "═".repeat(statusWidth) & "═╝"

  if comparison.missingInCurrent.len > 0:
    lines.add ""
    lines.add "Removed from current suite (present in baseline only):"
    for benchmarkName in comparison.missingInCurrent:
      lines.add "  • " & benchmarkName

  lines.add ""
  lines.add(
    "Legend: ▼ = improvement  ▲ = regression  ? = inconclusive  " &
    "= = unchanged  * = no baseline"
  )
  if comparison.baselineRuns < 2 or comparison.candidateRuns < 2:
    lines.add(
      "At least two runs per revision are required for a directional result."
    )

  result = lines.join("\n")
