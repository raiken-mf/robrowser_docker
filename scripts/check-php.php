<?php
// Temporarily copied into the smoke-test container, never into the image.
header('Content-Type: text/plain');
if (PHP_SAPI !== 'apache2handler'
    || PHP_VERSION_ID < 80427
    || PHP_VERSION_ID >= 80500
    || get_cfg_var('session.upload_progress.enabled') !== '0'
    || (extension_loaded('session') && ini_get('session.upload_progress.enabled') !== '0')) {
    http_response_code(500);
    exit("PHP runtime security check failed\n");
}
printf("PHP runtime security check passed (%s, %s)\n", PHP_VERSION, PHP_SAPI);
