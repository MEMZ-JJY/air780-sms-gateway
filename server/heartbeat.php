<?php

require __DIR__ . '/config.php';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    sms_auth(true);
    $d = json_decode(file_get_contents('php://input'), true);
    if (!is_array($d)) sms_fail('bad body');
    $st = array(
        'last'  => date('Y-m-d H:i:s'),
        'rsrp'  => intval($d['rsrp'] ?? 0),     
        'csq'   => intval($d['csq']  ?? 0),     
        'vbat'  => round(floatval($d['vbat'] ?? 0), 3),
        'temp'  => (string)($d['temp']  ?? ''),
        'iccid' => (string)($d['iccid'] ?? ''),
        'num'   => (string)($d['num']   ?? ''),
        'model' => (string)($d['model'] ?? ''),
    );
    @file_put_contents(STATUS_FILE, json_encode($st, JSON_UNESCAPED_UNICODE));
    sms_ok('ok', $st);
}


$st = file_exists(STATUS_FILE) ? json_decode(file_get_contents(STATUS_FILE), true) : array();
if (!is_array($st)) $st = array();
sms_ok('ok', $st);
