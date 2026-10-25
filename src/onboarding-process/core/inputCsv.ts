// Output / volume rows typed or pasted from a spreadsheet. Values stay text
// until saved; the database validates every row again.

export interface InputDraftRow { metric_key: string; label: string; quantity: string; std_minutes: string }

/**
 * One row per line: item code, description, quantity, minutes per unit
 * (comma, tab or semicolon separated). The description may be left out; a
 * header line or any line without numbers is skipped.
 */
export function parseInputCsv(text: string): InputDraftRow[] {
  return text.split(/\r?\n/)
    .map((line) => line.split(/[,\t;]/).map((cell) => cell.trim()))
    .filter((cells) => cells.length >= 3 && cells[0] !== ''
      && cells.slice(-2).every((cell) => cell !== '' && !Number.isNaN(Number(cell))))
    .map((cells) => cells.length >= 4
      ? { metric_key: cells[0], label: cells[1], quantity: cells[2], std_minutes: cells[3] }
      : { metric_key: cells[0], label: '', quantity: cells[1], std_minutes: cells[2] })
}
