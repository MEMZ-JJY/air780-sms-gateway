<?php

require __DIR__ . '/config.php';

$input = file_get_contents('php://input');
$data  = json_decode($input, true);

if (!$data || !is_array($data)) {
    http_response_code(400);
    echo 'bad request';
    exit;
}

if (SMS_ENABLE_TOKEN && ($data['token'] ?? '') !== SMS_TOKEN) {
    http_response_code(403);
    echo 'forbidden';
    exit;
}

$type = in_array($data['type'] ?? 'sms', array('sms', 'call', 'msg')) ? $data['type'] : 'sms';
$from = trim(isset($data['from']) ? (string)$data['from'] : '');
$content = trim(isset($data['content']) ? (string)$data['content'] : '');

if ($content === '') {
    if ($type === 'sms') {
        echo 'ok';
        exit;
    }
    
    $content = '来电';
}

$r = sms_write_line($type, $from, $content);
echo $r === 'dup' ? 'dup' : 'ok';
