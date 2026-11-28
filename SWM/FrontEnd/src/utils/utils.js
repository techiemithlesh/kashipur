import toast from "react-hot-toast";

export function normalizePayload(payload) {
  const dateFields = [
    "flatRegistryDate",
    "hoardingInstallationDate",
    "towerInstallationDate",
    "waterHarvestingDate",
    "dob",
  ];

  const normalized = { ...payload };

  // Convert 0/1 values to boolean (optional – keep if backend expects true/false)
  for (const key in normalized) {
    if (
      (normalized[key] === 0 || normalized[key] === 1) &&
      !key.endsWith("Id")
    ) {
      normalized[key] = Boolean(normalized[key]);
    }
  }

  // Fix normal date formats (dd-MM-yyyy → yyyy-MM-dd)
  dateFields.forEach((field) => {
    const value = normalized[field];
    if (value && typeof value === "string" && value.includes("-")) {
      const parts = value.split("-");
      if (parts[0].length === 2) {
        // dd-MM-yyyy → yyyy-MM-dd
        normalized[field] = `${parts[2]}-${parts[1]}-${parts[0]}`;
      }
    }
  });

  // Special case: floorDtl[].dateFrom → yyyy-MM
  if (normalized.floorDtl) {
    normalized.floorDtl = normalized.floorDtl.map((floor) => {
      const f = { ...floor };
      if (f.dateFrom) {
        const parts = f.dateFrom.split("-");
        if (parts[0].length === 2) {
          // dd-MM-yyyy → yyyy-MM
          f.dateFrom = `${parts[2]}-${parts[1]}`;
        } else if (parts.length === 3) {
          // yyyy-MM-dd → yyyy-MM
          f.dateFrom = `${parts[0]}-${parts[1]}`;
        }
      }
      return normalizePayload(f); // recursive for nested structures
    });
  }

  // Normalize ownerDtl recursively
  if (normalized.ownerDtl) {
    normalized.ownerDtl = normalized.ownerDtl.map((owner) =>
      normalizePayload(owner)
    );
  }

  return normalized;
}

export const toastMsg = (msg = "", type = "success", position = "top-right", duration = null) => {
  const options = {
    position,
  };

  if (duration) {
    options.autoClose = duration;   // toast duration in ms
  }

  if (toast[type]) {
    toast[type](msg, options);
  } else {
    toast.loading(msg, options); // fallback
  }
};

/**
 * Normalizes a date value to "YYYY-MM" for APIs that validate with date_format:Y-m.
 * "2025-04-01", "2025-04-01 00:00:00", "2025-04-01T00:00:00Z" or "2025-04" -> "2025-04".
 * ISO-like strings are sliced instead of parsed, so the month never shifts with the timezone.
 */
export const toYearMonth = (value) => {
  if (!value) return "";
  const match = /^(\d{4}-\d{2})/.exec(String(value));
  if (match) return match[1];

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
};


