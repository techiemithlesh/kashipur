<?php

namespace App\Http\Controllers\DBSystem;

use App\Http\Controllers\Controller;
use App\Models\DBSystem\Grievance;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use Illuminate\Support\Facades\Auth;

class GrievanceController extends Controller
{
    private function currentUlbId(): int
    {
        return (int) (app()->bound('CurrentUlbId') ? app('CurrentUlbId') : (Auth::user()->ulb_id ?? 1));
    }

    public function store(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'citizen_name' => 'required|string|max:150',
            'mobile' => 'required|string|regex:/^[0-9]{10}$/',
            'email' => 'nullable|email|max:190',
            'ward' => 'nullable|string|max:80',
            'address' => 'required|string|max:500',
            'category' => 'required|string|max:100',
            'subject' => 'required|string|max:180',
            'description' => 'required|string|max:5000',
        ]);
        if ($validator->fails()) {
            return response()->json(['status' => false, 'message' => 'Please check the form fields.', 'errors' => $validator->errors()], 422);
        }

        $grievance = Grievance::create([
            ...$validator->validated(),
            'ulb_id' => $request->input('ulb_id', 1),
            'reference_no' => 'GRV-' . now()->format('ymd') . '-' . strtoupper(Str::random(6)),
            'status' => 'Open',
        ]);

        return response()->json(['status' => true, 'message' => 'Grievance submitted successfully.', 'data' => [
            'reference_no' => $grievance->reference_no,
            'status' => $grievance->status,
            'created_at' => $grievance->created_at,
        ]], 201);
    }

    public function track(Request $request)
    {
        $validator = Validator::make($request->all(), [
            'mobile' => 'required|string|regex:/^[0-9]{10}$/',
            'reference_no' => 'nullable|string|max:30',
        ]);
        if ($validator->fails()) {
            return response()->json(['status' => false, 'message' => 'Enter a valid 10 digit mobile number.', 'errors' => $validator->errors()], 422);
        }

        $query = Grievance::where('mobile', $request->mobile)
            ->where('ulb_id', $request->input('ulb_id', 1));
        if ($request->filled('reference_no')) {
            $query->where('reference_no', strtoupper(trim($request->reference_no)));
        }
        $items = $query->orderByDesc('created_at')->get([
            'reference_no', 'category', 'subject', 'status', 'resolution_note', 'created_at', 'updated_at',
        ]);

        return response()->json(['status' => true, 'message' => 'Grievances retrieved.', 'data' => [
            'count' => $items->count(), 'items' => $items,
        ]]);
    }

    public function staffList(Request $request)
    {
        if (Auth::user()?->getTable() !== 'users') {
            return response()->json(['status' => false, 'message' => 'Staff access required.'], 403);
        }
        $query = Grievance::select("citizen_grievances.*","users.name as closed_by_name")
            ->leftJoin("users","users.id","citizen_grievances.closed_by")
            ->where('citizen_grievances.ulb_id', $this->currentUlbId())
            ->orderByDesc('citizen_grievances.created_at');
        if ($request->filled('status') && $request->status !== 'All') {
            $query->where('citizen_grievances.status', $request->status);
        }
        if ($request->filled('search')) {
            $search = trim($request->search);
            $query->where(function ($q) use ($search) {
                $q->where('citizen_grievances.reference_no', 'ilike', "%{$search}%")
                    ->orWhere('citizen_grievances.mobile', 'ilike', "%{$search}%")
                    ->orWhere('citizen_grievances.citizen_name', 'ilike', "%{$search}%")
                    ->orWhere('citizen_grievances.subject', 'ilike', "%{$search}%");
            });
        }
        return response()->json(['status' => true, 'message' => 'Grievance list retrieved.', 'data' => $query->limit(500)->get()]);
    }

    public function close(Request $request)
    {
        if (Auth::user()?->getTable() !== 'users') {
            return response()->json(['status' => false, 'message' => 'Staff access required.'], 403);
        }
        $validator = Validator::make($request->all(), [
            'id' => 'required|integer',
            'resolution_note' => 'nullable|string|max:2000',
        ]);
        if ($validator->fails()) {
            return response()->json(['status' => false, 'message' => 'Invalid grievance details.', 'errors' => $validator->errors()], 422);
        }
        $grievance = Grievance::where('ulb_id', $this->currentUlbId())->find($request->id);
        if (!$grievance) {
            return response()->json(['status' => false, 'message' => 'Grievance not found.'], 404);
        }
        $grievance->status = 'Closed';
        $grievance->resolution_note = $request->resolution_note;
        $grievance->closed_by = Auth::id();
        $grievance->closed_at = Carbon::now();
        $grievance->save();
        return response()->json(['status' => true, 'message' => 'Grievance closed.', 'data' => $grievance]);
    }
}
