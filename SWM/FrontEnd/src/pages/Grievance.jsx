import { useState } from "react";
import axios from "axios";
import { FaClipboardCheck, FaSearch, FaBullhorn } from "react-icons/fa";
import Layout from "../layout/Layout";
import { grievanceSubmitApi, grievanceTrackApi } from "../api/endpoints";

const initialForm = { citizen_name: "", mobile: "", email: "", ward: "", address: "", category: "", subject: "", description: "" };
const categories = [
  "Missed waste collection",
  "Irregular door-to-door collection",
  "Overflowing community bin",
  "Street sweeping and cleanliness",
  "Illegal dumping or littering",
  "Waste segregation and recycling",
  "Bulk or construction waste",
  "Waste vehicle or collection staff",
  "Other solid waste issue",
];

export default function Grievance() {
  const [tab, setTab] = useState("submit");
  const [form, setForm] = useState(initialForm);
  const [mobile, setMobile] = useState("");
  const [reference, setReference] = useState("");
  const [items, setItems] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [submittedMobile, setSubmittedMobile] = useState("");
  const update = (e) => setForm({ ...form, [e.target.name]: e.target.value });

  const submit = async (e) => {
    e.preventDefault(); setBusy(true); setError(""); setConfirmation("");
    try {
      const { data } = await axios.post(grievanceSubmitApi, form);
      setConfirmation(data?.data?.reference_no || "Submitted");
      setSubmittedMobile(form.mobile);
      setForm(initialForm);
    } catch (err) {
      setError(err.response?.data?.message || "Could not submit your grievance. Please try again.");
    } finally { setBusy(false); }
  };

  const track = async (e) => {
    e.preventDefault(); setBusy(true); setError(""); setItems(null);
    try {
      const { data } = await axios.post(grievanceTrackApi, { mobile, reference_no: reference || undefined });
      setItems(data?.data || { count: 0, items: [] });
    } catch (err) {
      setError(err.response?.data?.message || "Could not retrieve grievances. Check your mobile number.");
    } finally { setBusy(false); }
  };

  return <Layout title="Citizen Grievance | Municipal Services">
    <main className="mx-auto max-w-5xl px-4 py-10 md:px-8">
      <div className="mb-8 rounded-2xl bg-gradient-to-r from-emerald-800 to-teal-700 p-7 text-white md:p-10">
        <p className="mb-2 text-sm font-semibold uppercase tracking-widest text-emerald-100">Citizen help desk</p>
        <h1 className="text-3xl font-bold md:text-4xl">Grievance Redressal</h1>
        <p className="mt-3 max-w-2xl text-emerald-50">Submit a civic issue without creating an account. Keep your reference number and mobile number to check progress anytime.</p>
      </div>
      <div className="mb-6 flex gap-2 rounded-xl bg-gray-100 p-1">
        <button onClick={() => { setTab("submit"); setError(""); }} className={`flex flex-1 items-center justify-center gap-2 rounded-lg px-4 py-3 font-semibold ${tab === "submit" ? "bg-white text-emerald-800 shadow" : "text-gray-600"}`}><FaBullhorn /> Lodge a grievance</button>
        <button onClick={() => { setTab("track"); setError(""); }} className={`flex flex-1 items-center justify-center gap-2 rounded-lg px-4 py-3 font-semibold ${tab === "track" ? "bg-white text-emerald-800 shadow" : "text-gray-600"}`}><FaSearch /> Track grievance</button>
      </div>
      {error && <div role="alert" className="mb-5 rounded-lg border border-red-200 bg-red-50 p-3 text-red-800">{error}</div>}
      {confirmation && <div role="status" className="mb-5 rounded-xl border border-green-200 bg-green-50 p-5 text-green-900"><div className="flex items-center gap-2 font-bold"><FaClipboardCheck /> Grievance submitted</div><p className="mt-2">Your reference number is <strong className="text-lg">{confirmation}</strong>. Save it to track this request.</p><button onClick={() => { setTab("track"); setReference(confirmation); setMobile(submittedMobile); setConfirmation(""); }} className="mt-3 underline">Track this grievance</button></div>}

      {tab === "submit" ? <form onSubmit={submit} className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm md:p-8">
        <h2 className="mb-5 text-xl font-bold">Your details and issue</h2>
        <div className="grid gap-4 md:grid-cols-2">
          <Field label="Full name *"><input required maxLength="150" name="citizen_name" value={form.citizen_name} onChange={update} autoComplete="name" /></Field>
          <Field label="Mobile number *"><input required inputMode="numeric" pattern="[0-9]{10}" maxLength="10" name="mobile" value={form.mobile} onChange={update} placeholder="10 digit mobile number" autoComplete="tel-national" /></Field>
          <Field label="Email (optional)"><input type="email" maxLength="190" name="email" value={form.email} onChange={update} autoComplete="email" /></Field>
          <Field label="Ward (optional)"><input maxLength="80" name="ward" value={form.ward} onChange={update} /></Field>
          <Field label="Grievance category *"><select required name="category" value={form.category} onChange={update}><option value="">Select category</option>{categories.map((c) => <option key={c}>{c}</option>)}</select></Field>
          <Field label="Subject *"><input required maxLength="180" name="subject" value={form.subject} onChange={update} /></Field>
          <div className="md:col-span-2"><Field label="Issue location / address *"><input required maxLength="500" name="address" value={form.address} onChange={update} /></Field></div>
          <div className="md:col-span-2"><Field label="Describe the issue *"><textarea required rows="5" maxLength="5000" name="description" value={form.description} onChange={update} /></Field></div>
        </div>
        <button disabled={busy} className="mt-6 rounded-lg bg-emerald-800 px-6 py-3 font-semibold text-white hover:bg-emerald-900 disabled:opacity-60">{busy ? "Submitting…" : "Submit grievance"}</button>
      </form> : <section className="rounded-2xl border border-gray-200 bg-white p-5 shadow-sm md:p-8">
        <h2 className="mb-2 text-xl font-bold">Find your grievances</h2><p className="mb-5 text-gray-600">Enter the mobile number used when submitting. Add a reference number to look up one request.</p>
        <form onSubmit={track} className="grid gap-4 md:grid-cols-[1fr_1fr_auto] md:items-end">
          <Field label="Mobile number *"><input required inputMode="numeric" pattern="[0-9]{10}" maxLength="10" value={mobile} onChange={(e) => setMobile(e.target.value)} /></Field>
          <Field label="Reference number (optional)"><input value={reference} onChange={(e) => setReference(e.target.value.toUpperCase())} placeholder="e.g. GRV-261117-ABC123" /></Field>
          <button disabled={busy} className="rounded-lg bg-emerald-800 px-5 py-3 font-semibold text-white disabled:opacity-60">{busy ? "Searching…" : "Check status"}</button>
        </form>
        {items && <div className="mt-7"><p className="mb-3 font-semibold">You have submitted <span className="text-emerald-800">{items.count}</span> {items.count === 1 ? "grievance" : "grievances"}.</p>{items.count === 0 ? <p className="rounded-lg bg-gray-50 p-4 text-gray-600">No grievances found for these details.</p> : <div className="space-y-3">{items.items.map((item) => <article key={item.reference_no} className="rounded-xl border border-gray-200 p-4"><div className="flex flex-wrap items-center justify-between gap-3"><div><p className="font-bold text-emerald-900">{item.reference_no}</p><p className="text-sm text-gray-500">{item.category} · {new Date(item.created_at).toLocaleDateString()}</p></div><span className={`rounded-full px-3 py-1 text-sm font-semibold ${item.status?.toLowerCase() === "closed" || item.status?.toLowerCase() === "resolved" ? "bg-green-100 text-green-800" : "bg-amber-100 text-amber-800"}`}>{item.status}</span></div><p className="mt-2 font-medium">{item.subject}</p>{item.resolution_note && <p className="mt-2 rounded bg-green-50 p-3 text-sm text-green-900"><strong>Update:</strong> {item.resolution_note}</p>}</article>)}</div>}</div>}
      </section>}
    </main>
  </Layout>;
}

function Field({ label, children }) {
  return <label className="block text-sm font-semibold text-gray-700">{label}<span className="mt-1.5 block [&_input]:w-full [&_input]:rounded-lg [&_input]:border [&_input]:border-gray-300 [&_input]:px-3 [&_input]:py-2.5 [&_input]:font-normal [&_select]:w-full [&_select]:rounded-lg [&_select]:border [&_select]:border-gray-300 [&_select]:bg-white [&_select]:px-3 [&_select]:py-2.5 [&_textarea]:w-full [&_textarea]:rounded-lg [&_textarea]:border [&_textarea]:border-gray-300 [&_textarea]:px-3 [&_textarea]:py-2.5 [&_textarea]:font-normal">{children}</span></label>;
}
