import { useCallback, useEffect, useMemo, useState } from "react";
import axios from "axios";
import { FaCheck, FaRedo, FaSearch, FaCalendarAlt, FaMapMarkerAlt, FaPhoneAlt } from "react-icons/fa";
import AdminLayout from "../layout/AdminLayout";
import { getToken } from "../utils/auth";
import { grievanceCloseApi, grievanceStaffListApi } from "../api/endpoints";

const statusOptions = ["Open", "Closed", "All"];

export default function GrievanceManagement() {
  const [grievances, setGrievances] = useState([]);
  const [status, setStatus] = useState("Open");
  const [search, setSearch] = useState("");
  const [notes, setNotes] = useState({});
  const [loading, setLoading] = useState(false);
  const [closingId, setClosingId] = useState(null);
  const [error, setError] = useState("");

  const user = JSON.parse(localStorage.getItem("userDetails") || "{}");
  const token = getToken();
  const headers = useMemo(() => ({
    Authorization: `Bearer ${token}`,
    ...(user.ulbId ? { "X-ULB-ID": user.ulbId } : {}),
  }), [token, user.ulbId]);

  const loadGrievances = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const response = await axios.post(
        grievanceStaffListApi,
        { status, search },
        { headers }
      );
      setGrievances(response.data?.data || []);
    } catch (err) {
      setError(err.response?.data?.message || "Unable to load grievances.");
    } finally {
      setLoading(false);
    }
  }, [status, search, headers]);

  useEffect(() => {
    loadGrievances();
  }, [loadGrievances]);

  async function closeGrievance(id) {
    setClosingId(id);
    setError("");
    try {
      await axios.post(
        grievanceCloseApi,
        { id, resolution_note: notes[id] || "" },
        { headers }
      );
      await loadGrievances();
    } catch (err) {
      setError(err.response?.data?.message || "Unable to close this grievance.");
    } finally {
      setClosingId(null);
    }
  }

  const closedCount = grievances.filter((item) => item.status === "Closed").length;

  return (
    <AdminLayout>
      <main className="mx-auto max-w-6xl space-y-5">
        <header className="relative isolate overflow-hidden flex flex-wrap items-center justify-between gap-4 rounded-2xl bg-gradient-to-br from-slate-950 via-teal-950 to-emerald-800 p-6 text-white shadow-xl md:p-8">
          <div className="pointer-events-none absolute -right-12 -top-20 -z-10 h-64 w-64 rounded-full border-[32px] border-white/5" />
          <div>
            <p className="mb-2 inline-flex rounded-full border border-teal-200/20 bg-white/10 px-3 py-1 text-xs font-semibold uppercase tracking-[0.18em] text-teal-100">Citizen service desk</p>
            <h1 className="text-2xl font-bold md:text-3xl">Grievance Management</h1>
            <p className="mt-2 max-w-xl text-sm text-teal-50">Review citizen requests, follow their progress, and close resolved cases.</p>
          </div>
          <button onClick={loadGrievances} className="inline-flex items-center gap-2 rounded-lg border border-white/30 bg-white/10 px-4 py-2 font-semibold text-white transition hover:bg-white/20">
            <FaRedo /> Refresh
          </button>
        </header>

        {error && <p role="alert" className="rounded-lg border border-red-200 bg-red-50 p-3 text-red-800">{error}</p>}

        <div className="grid gap-3 sm:grid-cols-3">
          <SummaryCard label="Showing" value={grievances.length} color="text-slate-900" detail="Matching this view" />
          <SummaryCard label="Open" value={grievances.filter((item) => item.status !== "Closed").length} color="text-amber-700" detail="Needs attention" />
          <SummaryCard label="Closed" value={closedCount} color="text-emerald-700" detail="Resolved requests" />
        </div>

        <section className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
          <div className="flex flex-col gap-3 border-b border-slate-100 bg-slate-50/80 p-4 md:flex-row md:items-center md:justify-between">
            <nav className="flex gap-1 rounded-xl bg-slate-200/70 p-1" aria-label="Filter grievances">
              {statusOptions.map((option) => (
                <button key={option} onClick={() => setStatus(option)} className={`rounded-lg px-4 py-2 text-sm font-semibold transition ${status === option ? "bg-white text-teal-900 shadow-sm" : "text-slate-600 hover:text-slate-900"}`}>
                  {option}
                </button>
              ))}
            </nav>
            <label className="flex items-center gap-2 rounded-xl border border-slate-200 bg-white px-3 py-2 text-slate-400 shadow-sm focus-within:border-teal-500 focus-within:ring-2 focus-within:ring-teal-100">
              <FaSearch />
              <input className="min-w-0 bg-transparent text-sm text-slate-800 outline-none placeholder:text-slate-400 md:w-72" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search name, mobile, reference" />
            </label>
          </div>

          <div className="flex items-center justify-between border-b border-slate-100 px-5 py-3 text-sm text-slate-500">
            <span>Showing <strong className="text-slate-800">{grievances.length}</strong> {grievances.length === 1 ? "grievance" : "grievances"}</span>
            {loading && <span className="text-teal-700">Updating…</span>}
          </div>

          {loading && grievances.length === 0 ? <p className="p-12 text-center text-slate-500">Loading grievances…</p> : grievances.length === 0 ? <div className="p-12 text-center"><div className="mx-auto mb-3 flex h-12 w-12 items-center justify-center rounded-full bg-slate-100 text-slate-400"><FaSearch /></div><p className="font-semibold text-slate-700">No grievances found</p><p className="mt-1 text-sm text-slate-500">Try another status filter or search term.</p></div> : (
            <div className="space-y-4 bg-slate-50/60 p-4 md:p-5">
              {grievances.map((item) => (
                <article key={item.id} className="overflow-hidden rounded-xl border border-slate-200 bg-white shadow-sm transition hover:shadow-md">
                  <div className="space-y-4 border-l-4 border-teal-600 p-4 md:p-5">
                  <div className="flex flex-wrap items-start justify-between gap-4">
                    <div>
                      <div className="flex flex-wrap items-center gap-2">
                        <p className="font-bold tracking-wide text-teal-900">{item.reference_no}</p>
                        <span className={`rounded-full px-2.5 py-1 text-xs font-bold ${item.status === "Closed" ? "bg-emerald-100 text-emerald-800" : "bg-amber-100 text-amber-800"}`}>{item.status}</span>
                      </div>
                      <h2 className="mt-2 text-lg font-semibold text-slate-900">{item.subject}</h2>
                      <p className="mt-1 text-sm text-slate-500">{item.category}</p>
                    </div>
                    <p className="inline-flex items-center gap-2 rounded-lg bg-slate-50 px-3 py-2 text-xs text-slate-500"><FaCalendarAlt className="text-teal-700" />{new Date(item.created_at).toLocaleString()}</p>
                  </div>
                  <div className="grid gap-3 rounded-xl bg-slate-50 p-3 text-sm text-slate-700 md:grid-cols-2">
                    <p><strong className="text-slate-900">{item.citizen_name}</strong><span className="ml-2 inline-flex items-center gap-1 text-slate-500"><FaPhoneAlt className="text-xs" />{item.mobile}</span></p>
                    <p className="inline-flex items-start gap-2"><FaMapMarkerAlt className="mt-1 shrink-0 text-teal-700" /><span>{item.ward ? `Ward ${item.ward} · ` : ""}{item.address}</span></p>
                  </div>
                  <div><p className="mb-1 text-xs font-bold uppercase tracking-wider text-slate-400">Issue details</p><p className="whitespace-pre-wrap text-sm leading-relaxed text-slate-700">{item.description}</p></div>

                  {item.status === "Closed" ? (
                    <div className="rounded-xl border border-emerald-100 bg-emerald-50/80 p-4">
                      <p className="text-xs font-bold uppercase tracking-wider text-emerald-800">Resolution details</p>
                      <p className="mt-2 text-sm text-emerald-950">{item.resolution_note || "No resolution note provided."}</p>
                      <div className="mt-3 flex flex-wrap gap-x-6 gap-y-1 border-t border-emerald-100 pt-3 text-xs text-emerald-800"><span>Closed by: <strong>{item.closed_by_name || "Staff"}</strong></span><span>Closed: <strong>{item.closed_at || "—"}</strong></span></div>
                    </div>
                  ) : (
                    <div className="flex flex-col gap-3 border-t border-slate-100 pt-4 md:flex-row">
                      <textarea className="min-h-11 flex-1 rounded-xl border border-slate-200 px-3 py-2 text-sm outline-none transition placeholder:text-slate-400 focus:border-teal-500 focus:ring-2 focus:ring-teal-100" value={notes[item.id] || ""} onChange={(e) => setNotes({ ...notes, [item.id]: e.target.value })} placeholder="Add a resolution note for the citizen (optional)" />
                      <button disabled={closingId === item.id} onClick={() => closeGrievance(item.id)} className="inline-flex items-center justify-center gap-2 rounded-xl bg-emerald-700 px-5 py-2.5 font-semibold text-white shadow-sm transition hover:bg-emerald-800 disabled:cursor-wait disabled:opacity-60">
                        <FaCheck /> {closingId === item.id ? "Closing…" : "Close grievance"}
                      </button>
                    </div>
                  )}
                  </div>
                </article>
              ))}
            </div>
          )}
        </section>
      </main>
    </AdminLayout>
  );
}

function SummaryCard({ label, value, color, detail }) {
  return (
    <div className="rounded-xl border border-slate-200 bg-white px-4 py-3 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md">
      <p className="text-xs font-semibold uppercase tracking-wider text-slate-500">{label}</p>
      <div className="mt-1 flex items-end justify-between gap-2"><p className={`text-2xl font-bold ${color}`}>{value}</p><p className="text-xs text-slate-400">{detail}</p></div>
    </div>
  );
}
