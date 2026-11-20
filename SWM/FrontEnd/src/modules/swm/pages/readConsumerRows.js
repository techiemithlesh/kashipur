import { utils } from "xlsx";

const text = (value) => String(value ?? "").trim();
const wardKey = (value) => text(value).replace(/\s+/g, " ").toUpperCase();

function readSheet(sheet, name) {
  const [header = [], ...rows] = utils.sheet_to_json(sheet, {
    header: 1,
    raw: true,
    defval: null,
  });
  const columns = new Map(header.map((label, index) => [text(label).toLowerCase(), index]));
  if (!columns.has("uniqueid")) {
    throw new Error(`${name} is missing the UniqueID column.`);
  }

  const parsedRows = [];
  for (const [index, row] of rows.entries()) {
    if (!row.some((value) => text(value))) continue;

    // Keep original headers so new file columns are available automatically.
    const fields = new Map();
    for (const [columnIndex, headerLabel] of header.entries()) {
      const label = text(headerLabel);
      if (label) fields.set(label, row[columnIndex] ?? null);
    }

    parsedRows.push({
      get: (column) => text(row[columns.get(column.toLowerCase())]),
      sourceFields: Object.fromEntries(fields),
      sourceRow: index + 2,
    });
  }
  return parsedRows;
}

export function readConsumerRows(workbook, { isCsv = false } = {}) {
  const masterName = "All Wards Data Format";
  const master = workbook.Sheets[isCsv ? workbook.SheetNames[0] : masterName];
  if (isCsv && !master) throw new Error("The CSV has no readable data.");
  if (!master) throw new Error(`The workbook must contain the ${masterName} sheet.`);

  const wardById = new Map();
  const numbersByName = new Map();
  for (const name of workbook.SheetNames) {
    const match = /^Ward-(\d+) Data$/i.exec(name);
    if (!match) continue;

    const wardNumber = Number(match[1]);
    for (const { get, sourceFields } of readSheet(workbook.Sheets[name], name)) {
      const sourceId = get("UniqueID");
      if (!sourceId) continue;

      if (wardById.has(sourceId)) {
        throw new Error(`UniqueID ${sourceId} occurs more than once in the ward sheets.`);
      }

      wardById.set(sourceId, {
        wardNumber,
        sourceFields,
        latitude: get("Latitude(Y)") || null,
        longitude: get("Longitude (X)") || null,
        mobileNo: get("Mobile No"),
      });
      const nameKey = wardKey(get("WardName_1"));
      if (nameKey) {
        if (!numbersByName.has(nameKey)) numbersByName.set(nameKey, new Set());
        numbersByName.get(nameKey).add(wardNumber);
      }
    }
  }

  const seen = new Set();
  return readSheet(master, isCsv ? "CSV" : masterName).map(({ get, sourceFields, sourceRow }) => {
    const sourceId = get("UniqueID");
    if (sourceId && seen.has(sourceId)) {
      throw new Error(`UniqueID ${sourceId} occurs more than once in the master sheet.`);
    }
    if (sourceId) seen.add(sourceId);

    const matchingNumbers = numbersByName.get(wardKey(get("WardName_1")));
    const ward = wardById.get(sourceId);
    const csvWard = get("wardNumber") || get("wardNo") || get("wandNo");
    const parsedWard = /^\d+$/.test(csvWard) ? Number(csvWard) : null;
    const csvWardNumber =
      Number.isSafeInteger(parsedWard) && parsedWard > 0 ? parsedWard : null;
    return {
      // The combined sheet takes precedence when both sheets have the same header.
      ...sourceFields,
      sourceRow,
      sourceId,
      wardNumber: isCsv
        ? csvWardNumber
        : ward?.wardNumber ?? (matchingNumbers?.size === 1 ? [...matchingNumbers][0] : null),
      address: get("Address") || null,
      ownerName: get("New Owner Name(If Not Matched)") || get("Owner Name") || null,
      mobileNo: get("Mobile No") || ward?.mobileNo || null,
      guardianName:get("Father Husband Name") || null,
      latitude: isCsv ? get("Latitude(Y)") || null : ward?.latitude ?? null,
      longitude: isCsv ? get("Longitude (X)") || null : ward?.longitude ?? null,
    };
  });
}
