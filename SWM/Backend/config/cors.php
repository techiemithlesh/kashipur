<?php

// Browser cross-origin access to the API (Laravel's global HandleCors middleware).
// Production serves the web app on kashipurcontrolcentre.com and the API on
// api.kashipurcontrolcentre.com, so only the web app's origins may call /api from a browser.
// Mobile apps and server-to-server calls send no Origin header and are unaffected.
// ALLOWED_ORIGINS: comma-separated, e.g. https://kashipurcontrolcentre.com,https://www.kashipurcontrolcentre.com

return [

    'paths' => ['api/*', 'sanctum/csrf-cookie'],

    'allowed_methods' => ['*'],

    'allowed_origins' => array_values(array_filter(array_map('trim', explode(',', (string) env('ALLOWED_ORIGINS', env('APP_URL', '')))))),

    'allowed_origins_patterns' => [],

    'allowed_headers' => ['*'],

    'exposed_headers' => [],

    'max_age' => 3600,

    'supports_credentials' => false,

];
