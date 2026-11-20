<?php

namespace App\Bll\SWM;

use App\Models\DBSystem\UlbWardMaster;
use App\Models\SWM\Consumer;
use App\Models\SWM\ConsumerOwner;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class ConsumerImportBll
{
    public function process(Request $request, bool $commit)
    {
        $user = $request->user();
        abort_unless($user && $user->getTable() === 'users' && $user->ulb_id, 403);
        abort_unless($user->getRoleDetailsByUserId()->get()->contains(
            fn ($role) => in_array(strtoupper($role->role_name), ['ADMIN', 'SUPER ADMIN'], true)
        ), 403, 'Consumer import requires a municipal administrator.');

        $input = $request->validate([
            'rows' => ['required', 'array', 'max:250'],
            'rows.*' => ['required', 'array'],
        ]);

        $ulbId = $user->ulb_id;
        $wards = (new UlbWardMaster())->getNumericWardList($ulbId)
            ->groupBy(fn ($ward) => (int) $ward->ward_no);
        $sourceIds = collect($input['rows'])->pluck('sourceId')->filter(
            fn ($id) => is_string($id) && strlen($id) <= 100
        );
        $counts = $sourceIds->countBy();
        $existing = Consumer::whereIn('consumer_no', $sourceIds->all())->pluck('consumer_no')->flip();
        $connection = (new Consumer())->getConnection();
        $results = [];

        foreach ($input['rows'] as $row) {
            $validator = Validator::make($row, [
                'sourceRow' => ['required', 'integer', 'min:2'],
                'sourceId' => ['required', 'string', 'max:100'],
                'wardNumber' => ['required', 'integer', 'min:1'],
                'ownerName' => ['nullable', 'string', 'max:255'],
                'address' => ['nullable', 'string', 'max:200'],
                'mobileNo' => ['nullable', 'digits:10'],
                'latitude' => ['nullable', 'numeric', 'between:-90,90'],
                'longitude' => ['nullable', 'numeric', 'between:-180,180'],
            ]);
            $result = ['sourceRow' => $row['sourceRow'] ?? null];
            if ($validator->fails()) {
                $results[] = $result + ['status' => 'invalid', 'message' => implode(' ', $validator->errors()->all())];
                continue;
            }
            $row = array_replace($row, $validator->validated());
            $sourceId = $row['sourceId'];
            if ($counts->get($sourceId) > 1) {
                $results[] = $result + [
                    'status' => 'invalid',
                    'message' => 'UniqueID occurs more than once in the submitted batch.',
                ];
                continue;
            }

            $matches = $wards->get((int) $row['wardNumber']);
            if ($matches?->count() !== 1) {
                $results[] = $result + [
                    'status' => 'invalid',
                    'message' => 'Ward number does not match exactly one ward in your municipality.',
                ];
                continue;
            }
            if ($existing->has($sourceId)) {
                $results[] = $result + ['status' => 'existing'];
                continue;
            }
            // Preview reports which rows are ready. Only commit saves them.
            if (!$commit) {
                $results[] = $result + ['status' => 'ready'];
                continue;
            }

            try {
                $connection->transaction(function () use ($row, $matches, $user, $ulbId) {
                    $consumer = Consumer::create([
                        "gis_id"=>$row['UniqueID'] ?? null,
                        'consumer_no' => $row['sourceId'],
                        'ulb_id' => $ulbId,
                        'ward_mstr_id' => $matches->first()->id,
                        'address' => $row['address'] ?? null,
                        'latitude' => $row['latitude'] ?? null,
                        'longitude' => $row['longitude'] ?? null,
                        'user_id' => $user->id,
                    ]);
                    if (isset($row['ownerName']) || isset($row['mobileNo'])) {
                        ConsumerOwner::create([
                            'consumer_id' => $consumer->id,
                            'owner_name' => $row['ownerName'] ?? null,
                            "guardian_name" => $row['guardianName'] ?? null,
                            "relation_type" => $row['relation'] ?? null,
                            'mobile_no' => $row['mobileNo'] ?? null,
                            'user_id' => $user->id,
                        ]);
                    }
                });
                $results[] = $result + ['status' => 'imported'];
            } catch (UniqueConstraintViolationException $error) {
                if (!Consumer::where('consumer_no', $sourceId)->exists()) {
                    throw $error;
                }
                $results[] = $result + ['status' => 'existing'];
            }
        }

        return responseMsg(true, 'Consumer import batch processed.', $results);
    }
}
