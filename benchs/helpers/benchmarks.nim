  # ###################################################################################################################################### #
 # ########################################################## PROFILER ################################################################## #
# ###################################################################################################################################### #

import times, math, algorithm, strutils, tables, unicode, std/monotimes, os

type
  Parameters* = object
    samples*: int
    warmup*: int
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
    timeRatio*: float      # candidate / baseline
    memRatio*: float
    timeImprovement*: float  # (baseline - candidate) / baseline
    memImprovement*: float
    isFaster*: bool
    usesLessMem*: bool



# ==================== Formating ====================

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

  # Format avec précision adaptée
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

# ==================== Calcul de statistiques ====================

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

  # Quartiles
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

# ==================== Affichage ====================

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
  echo "=" .repeat(70)
  echo "Benchmark: ", b.name
  echo "Samples: ", b.params.samples, " (warmup: ", b.params.warmup, ")"
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
  echo "=" .repeat(70)

proc notNaN(v:float):float =
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

  # Time comparison
  let timeIcon = if cmp.isFaster: "✓" else: "✗"
  let timeColor = if cmp.isFaster: "" else: ""
  echo "║ Time   : ", timeIcon, " ",
       (if cmp.isFaster: "FASTER" else: "SLOWER"), " by ",
       prettyPercent(abs(cmp.timeImprovement)),
       " (", cmp.timeRatio.formatFloat(ffDecimal, 2), "x)",
       " ".repeat(max(0, 48 - (if cmp.isFaster: 7 else: 6) - prettyPercent(abs(cmp.timeImprovement)).len - 3 - cmp.timeRatio.formatFloat(ffDecimal, 2).len)), "║"

  # Memory comparison
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
  result.params = Parameters(samples: sample, warmup: warm)
  result.times = newSeqOfCap[float](sample)
  result.mems = newSeqOfCap[float](sample)

template measure*(bench: var Benchmark, memBaseline: int, code: untyped) =
  let t0 = getMonoTime()
  code
  let elapsed = (getMonoTime() - t0).inNanoseconds.float / 1e9

  bench.times.add(elapsed)
  bench.mems.add((getOccupiedMem() - memBaseline).float)

template benchmark*(benchmarkName: string, sample, code: untyped): untyped =
  benchmark(benchmarkName, sample, 1, code)

template benchmark*(benchmarkName: string, sample, warm, code: untyped): untyped =
  var bench = initBenchmark(benchmarkName, sample, warm)

  block:
    for i in 0..<warm:
      code

    for i in 0..<sample:
      let memBaseline = getOccupiedMem()
      measure(bench, memBaseline):
        code

  finalize(bench)
  bench

template benchmarkWithSetup*(benchmarkName: string, sample,
                              setup, code: untyped): untyped =
  benchmarkWithSetup(benchmarkName, sample, 1, setup, code)

template benchmarkWithSetup*(benchmarkName: string, sample, warm,
                              setup, code: untyped): untyped =
  var bench = initBenchmark(benchmarkName, sample, warm)

  block:
    for i in 0..<warm:
      setup
      code

    for i in 0..<sample:
      let memBaseline = getOccupiedMem()
      setup
      measure(bench, memBaseline):
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

proc saveSummary*(suite: BenchmarkSuite, path: string) =
  var file = open(path, fmWrite)
  defer: file.close()

  file.writeLine(suite.name & ",time_median,mem_median,time_seconds,mem_bytes")

  for bench in suite.benchmarks:
    let mem = prettyMem(bench.memStats.median)
    let time = prettyTime(bench.timeStats.median)
    file.writeLine(
      bench.name & "," & time & "," & mem & "," &
      bench.timeStats.median.formatFloat(ffScientific, 10) & "," &
      bench.memStats.median.formatFloat(ffScientific, 10)
    )

type
  BenchResult* = object
    name*: string
    timeRatio*: float
    memRatio*: float
    timeImprovement*: float
    memImprovement*: float
    timeSignificant*: bool
    memSignificant*: bool
    timeBetter*: bool
    memBetter*: bool
    missingInBaseline*: bool

  BenchComp* = object
    suiteName*: string
    baselineFile*: string
    margin*: float
    results*: seq[BenchResult]
    missingInCurrent*: seq[string]


proc loadBenchmarkSuiteFromCsv*(path: string): BenchmarkSuite =
  result.benchmarks = @[]

  if fileExists(path):
    var file = open(path, fmRead)
    defer: file.close()

    var isFirst = true
    for line in file.lines:
      if isFirst:
        let headerParts = line.split(',', 1)
        result.name = if headerParts.len > 0: headerParts[0] else: "Baseline"
        isFirst = false
        continue

      let parts = line.split(',')
      if parts.len < 5:
        continue

      var bench = initBenchmark(parts[0], 1, 0)
      try:
        let t = parseFloat(parts[3])   # time_seconds
        let m = parseFloat(parts[4])   # mem_bytes
        bench.times.add(t)
        bench.mems.add(m)
        bench.timeStats = calculateStatistics(bench.times)
        bench.memStats = calculateStatistics(bench.mems)
        bench.totalTime = t
        bench.totalMem = m
        result.benchmarks.add(bench)
      except ValueError:
        continue

proc compareWithBaseline*(suite: BenchmarkSuite, csvPath: string,
                         margin: float = 0.05): BenchComp =
  result.suiteName = suite.name
  result.baselineFile = csvPath
  result.margin = margin
  result.results = @[]
  result.missingInCurrent = @[]

  let baseline = loadBenchmarkSuiteFromCsv(csvPath)

  var baselineMap = initTable[string, Benchmark]()
  for b in baseline.benchmarks:
    baselineMap[b.name] = b

  var currentNames = initTable[string, bool]()

  for current in suite.benchmarks:
    currentNames[current.name] = true
    var res: BenchResult
    res.name = current.name

    if not baselineMap.hasKey(current.name):
      res.missingInBaseline = true
      result.results.add(res)
      continue

    let base = baselineMap[current.name]

    res.timeRatio = current.timeStats.median / base.timeStats.median
    res.timeImprovement =
      (current.timeStats.median - base.timeStats.median) / base.timeStats.median
    res.timeBetter = res.timeImprovement < 0
    res.timeSignificant = abs(res.timeImprovement) > margin

    res.memRatio = current.memStats.median / base.memStats.median
    res.memImprovement =
      (current.memStats.median - base.memStats.median) / base.memStats.median
    res.memBetter = res.memImprovement < 0
    res.memSignificant = abs(res.memImprovement) > margin

    result.results.add(res)

  for name, _ in baselineMap:
    if not currentNames.hasKey(name):
      result.missingInCurrent.add(name)

proc `$`*(comp: BenchComp): string =
  var lines: seq[string] = @[]

  let innerWidth = 75

  lines.add ""
  lines.add "╔═" & "═".repeat(innerWidth) & "═╗"
  lines.add "║ " & ("Benchmark Comparison: " & comp.suiteName).alignLeft(innerWidth) & " ║"
  lines.add "║ " & ("Baseline: " & comp.baselineFile).alignLeft(innerWidth) & " ║"
  lines.add "║ " & ("Significance margin: " & prettyPercent(comp.margin)).alignLeft(innerWidth) & " ║"
  lines.add "╠═" & "═".repeat(24) & "═╪" & "═".repeat(11) & "═╪" & "═".repeat(11) & "═╪" & "═".repeat(23) & "═╣"
  lines.add "║ " & "Benchmark".alignLeft(24) & " │ " & "Time".alignLeft(10) & " │ " & "Memory".alignLeft(10) & " │ " & "Status".alignLeft(22) & " ║"
  lines.add "╠═" & "═".repeat(24) & "═╪" & "═".repeat(11) & "═╪" & "═".repeat(11) & "═╪" & "═".repeat(23) & "═╣"

  for res in comp.results:
    let name = (if res.missingInBaseline: res.name & "*" else: res.name).alignLeft(24)

    let timeTxt =
      if res.missingInBaseline:
        "N/A"
      elif res.timeSignificant:
        (if res.timeBetter: "▼ " else: "▲ ") & prettyPercent(res.timeImprovement)
      else:
        "≈ " & prettyPercent(abs(res.timeImprovement))

    let memTxt =
      if res.missingInBaseline:
        "N/A"
      elif res.memSignificant:
        (if res.memBetter: "▼ " else: "▲ ") & prettyPercent(res.memImprovement)
      else:
        "≈ " & prettyPercent(abs(res.memImprovement))

    var statusParts: seq[string] = @[]
    if not res.missingInBaseline:
      if res.timeSignificant:
        statusParts.add(if res.timeBetter: "FASTER" else: "SLOWER")
      if res.memSignificant:
        statusParts.add(if res.memBetter: "LESS MEM" else: "MORE MEM")

    let status =
      if res.missingInBaseline:
        "NEW (no baseline)"
      elif statusParts.len == 0:
        "stable"
      else:
        statusParts.join(" + ")

    lines.add "║ " & name & " │ " & timeTxt.alignLeft(10) & " │ " & memTxt.alignLeft(10) & " │ " & status.alignLeft(22) & " ║"

  lines.add "╚═" & "═".repeat(24) & "═╧" & "═".repeat(11) & "═╧" & "═".repeat(11) & "═╧" & "═".repeat(23) & "═╝"

  if comp.missingInCurrent.len > 0:
    lines.add ""
    lines.add "Removed from current suite (present in baseline only):"
    for m in comp.missingInCurrent:
      lines.add "  • " & m

  lines.add ""
  lines.add "Legend: ▼ = improvement  ▲ = regression  ≈ = within margin  * = no baseline"

  return lines.join("\n")
