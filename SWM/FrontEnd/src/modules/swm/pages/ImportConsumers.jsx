import { useState } from "react";
import { Link } from "react-router-dom";
import axios from "axios";
import { read } from "xlsx";
import {
  swmConsumerImportCommitApi,
  swmConsumerImportPreviewApi,
} from "../../../api/endpoints";
import { getToken } from "../../../utils/auth";
import { readConsumerRows } from "./readConsumerRows";

const batchSize = 250;
const inputClass = "mt-1 w-full rounded-md border border-slate-300 bg-white px-3 py-2";
const actionClass = "rounded-md bg-primary px-4 py-2 font-semibold text-white disabled:opacity-50";

async function post(url, payload) {
  const { data } = await axios.post(url, payload, {
    headers: { Authorization: `Bearer ${getToken()}` },
  });
  if (!data.status) throw new Error(data.message);
  return data.data;
}

function errorMessage(error) {
  return error.response?.data?.message || error.message || "The request failed.";
}

export default function ImportConsumers() {
  const [file, setFile] = useState(null);
  const [preview, setPreview] = useState(null);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState("");
  const [rowProgress, setRowProgress] = useState(null);
  const [error, setError] = useState("");
  const [issuePage, setIssuePage] = useState(0);

  async function processRows(url, rows, onBatch) {
    setRowProgress({ processed: 0, total: rows.length });
    // The API accepts up to 250 rows per request.
    for (let start = 0; start < rows.length; start += batchSize) {
      const batch = rows.slice(start, start + batchSize);
      const results = await post(url, { rows: batch });
      onBatch(results);
      setRowProgress({ processed: start + batch.length, total: rows.length });
    }
  }

  async function previewImport(event) {
    event.preventDefault();
    setBusy(true);
    setPreview(null);
    setError("");
    setProgress("Reading file…");
    setRowProgress(null);
    setIssuePage(0);
    try {
      const isCsv = /\.csv$/i.test(file.name);
      const workbook = isCsv
        ? read(await file.text(), { type: "string", raw: true })
        : read(await file.arrayBuffer(), { type: "array" });
      const rows = readConsumerRows(workbook, { isCsv });
      if (!rows.length) throw new Error("The file has no consumer rows.");

      setProgress("Validating rows…");
      const results = [];
      await processRows(swmConsumerImportPreviewApi, rows, (batch) => results.push(...batch));
      const byRow = new Map(rows.map((row) => [row.sourceRow, row]));
      setPreview({
        ready: results.filter((row) => row.status === "ready").map((row) => byRow.get(row.sourceRow)),
        existing: results.filter((row) => row.status === "existing").length,
        issues: results.filter((row) => row.status === "invalid"),
      });
      setProgress("Preview complete.");
    } catch (failure) {
      setError(errorMessage(failure));
      setProgress("");
    } finally {
      setBusy(false);
    }
  }

  async function importRows() {
    if (!preview?.ready.length) return;
    if (!window.confirm(`Import ${preview.ready.length.toLocaleString()} valid consumers with available owner details?`)) return;

    setBusy(true);
    setError("");
    setProgress("Importing consumers…");
    setPreview(null);
    let imported = 0;
    let existing = preview.existing;
    const issues = [...preview.issues];
    try {
      await processRows(swmConsumerImportCommitApi, preview.ready, (results) => {
        for (const result of results) {
          if (result.status === "imported") imported += 1;
          if (result.status === "existing") existing += 1;
          if (result.status === "invalid") issues.push(result);
        }
      });
      setProgress(`Imported ${imported.toLocaleString()} consumers.`);
      setPreview({ ready: [], existing, issues });
    } catch (failure) {
      setProgress(`${imported.toLocaleString()} imports confirmed.`);
      setError(`${errorMessage(failure)} Run a new preview before trying again. Saved rows will be skipped.`);
    } finally {
      setBusy(false);
    }
  }

  const pageSize = 25;
  const issues = preview?.issues ?? [];
  return (
    <main className="mx-auto max-w-5xl space-y-6 p-4 sm:p-6">
      <header>
        <Link to="/swm/add" className="text-sm font-semibold text-primary hover:underline">Add a single consumer</Link>
        <h1 className="mt-2 text-2xl font-bold text-slate-900">Import consumers</h1>
      </header>

      <form onSubmit={previewImport} className="rounded-xl border border-slate-200 bg-white p-5 shadow-sm">
        <fieldset disabled={busy} className="space-y-4">
          <label className="block">
            Excel workbook or CSV
            <input required type="file" accept=".xlsx,.csv" className={inputClass} onChange={(event) => {
              setFile(event.target.files[0] || null);
              setPreview(null);
              setProgress("");
              setRowProgress(null);
              setError("");
            }} />
          </label>
        </fieldset>
        <button type="submit" disabled={busy || !file} className={`mt-5 ${actionClass}`}>Preview import</button>
      </form>

      {progress && <p role="status" className="text-sm text-slate-700">{progress}</p>}
      {rowProgress && (
        <label className="block text-sm text-slate-700">
          {rowProgress.processed.toLocaleString()} of{" "}
          {rowProgress.total.toLocaleString()} rows processed (
          {Math.floor((rowProgress.processed / rowProgress.total) * 100)}%)
          <progress
            className="mt-2 block w-full accent-primary"
            value={rowProgress.processed}
            max={rowProgress.total}
          />
        </label>
      )}
      {error && <p role="alert" className="rounded-md bg-red-50 p-3 text-red-800">{error}</p>}

      {preview && (
        <section aria-labelledby="import-results" className="space-y-4 rounded-xl border border-slate-200 bg-white p-5">
          <h2 id="import-results" className="text-lg font-semibold">Import results</h2>
          <p className="text-sm text-slate-700">
            {preview.ready.length.toLocaleString()} ready · {preview.existing.toLocaleString()} already imported · {issues.length.toLocaleString()} need correction
          </p>
          {issues.length > 0 && (
            <>
              <table className="w-full text-left text-sm">
                <thead className="bg-slate-100">
                  <tr><th scope="col" className="p-2">Master sheet row</th><th scope="col" className="p-2">Issue</th></tr>
                </thead>
                <tbody>
                  {issues.slice(issuePage * pageSize, (issuePage + 1) * pageSize).map(({ sourceRow, message }) => (
                    <tr key={sourceRow} className="border-b border-slate-100">
                      <td className="p-2">{sourceRow}</td><td className="p-2">{message}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              <div className="flex items-center gap-4 text-sm">
                <button type="button" disabled={issuePage === 0} onClick={() => setIssuePage(issuePage - 1)}
                  className="text-primary disabled:opacity-50">Previous</button>
                <span>Page {issuePage + 1} of {Math.ceil(issues.length / pageSize)}</span>
                <button type="button" disabled={(issuePage + 1) * pageSize >= issues.length}
                  onClick={() => setIssuePage(issuePage + 1)} className="text-primary disabled:opacity-50">Next</button>
              </div>
            </>
          )}
          {preview.ready.length > 0 && (
            <button type="button" disabled={busy} onClick={importRows} className={actionClass}>Import valid rows</button>
          )}
        </section>
      )}
    </main>
  );
}
