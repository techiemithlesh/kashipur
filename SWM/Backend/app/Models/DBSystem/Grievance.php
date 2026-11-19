<?php

namespace App\Models\DBSystem;

class Grievance extends ParamModel
{
    protected $table = 'citizen_grievances';

    protected $fillable = [
        'ulb_id', 'reference_no', 'citizen_name', 'mobile', 'email', 'ward',
        'address', 'category', 'subject', 'description', 'status', 'resolution_note',"closed_by","closed_at"
    ];
}
