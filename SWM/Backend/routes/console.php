<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Schedule;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote')->hourly();

// Queue workers run in their own container (docker-compose.yml "queue" service), not from the scheduler.

// Monthly consumer demand generation. The command itself only acts on the last day of the month
// (app timezone), so it is checked daily; the jobs it dispatches are processed by the queue worker.
Schedule::command('swm:generate-demand-command-monthly')
    ->dailyAt('01:00')
    ->withoutOverlapping()
    ->onOneServer();
