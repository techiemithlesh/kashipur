<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::connection('pgsql')->create('citizen_grievances', function (Blueprint $table) {
            $table->bigIncrements('id');
            $table->unsignedBigInteger('ulb_id')->default(1)->index();
            $table->string('reference_no', 30)->unique();
            $table->string('citizen_name', 150);
            $table->string('mobile', 10)->index();
            $table->string('email', 190)->nullable();
            $table->string('ward', 80)->nullable();
            $table->string('address', 500);
            $table->string('category', 100);
            $table->string('subject', 180);
            $table->text('description');
            $table->string('status', 30)->default('Open')->index();
            $table->text('resolution_note')->nullable();
            $table->timestamps();
            $table->index(['ulb_id', 'mobile', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::connection('pgsql')->dropIfExists('citizen_grievances');
    }
};
