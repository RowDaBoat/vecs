import strutils

proc separator(sides: string, widths: seq[int]): string =
  result &= sides

  for width in widths:
    result &= repeat("-", width + 2)

  result &= repeat("-", widths.len - 1)
  result &= sides & "\n"

proc lineText(data: seq[seq[seq[string]]], widths: seq[int], row: int, line: int): string =
  result &= "|"

  for columnIndex, width in widths:
    let cell = data[columnIndex][row]

    if line >= cell.len:
      result &= repeat(" ", width + 2) & "|"
    else:
      let text = cell[line]
      result &= " " & text & repeat(" ", width - text.len) & " |"

  result &= "\n"

proc maxLen(strSeq: seq[string]): int =
  for s in strSeq:
    result = max(result, s.len)

proc maxHeight(data: seq[seq[seq[string]]], row: int): int =
  for column in data:
    result = max(result, column[row].len)

proc computeWidths(data: seq[seq[seq[string]]], columns: int): seq[int] =
  result.setLen(columns)

  for index, column in data:
    for cell in column:
      result[index] = max(result[index], maxLen(cell))

proc textTable*(data: seq[seq[seq[string]]]): string =
  let widths = computeWidths(data, data.len)

  result &= separator(".", widths)

  for row in 0 ..< data[0].len:  
    let lines = maxHeight(data, row)
    for line in 0 ..< lines:
      result &= lineText(data, widths, row, line)

    if row < data[0].len - 1:
      result &= separator("|", widths)

  result &= separator("'", widths)
