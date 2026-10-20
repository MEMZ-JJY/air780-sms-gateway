<?php

require __DIR__ . '/config.php';

$act = $_SERVER['REQUEST_METHOD'] === 'POST'
    ? (req_body()['action'] ?? 'done')
    : 'take';

function req_body()
{
    $d = json_decode(file_get_contents('php://input'), true);
    return is_array($d) ? $d : array();
}

if ($act === 'take') {
    sms_auth(true);
    $list = outbox_take();
    $items = array();
    foreach ($list as $x) {
        $items[] = array(
            'id'      => $x['id'],
            'num'     => $x['num'] ?? '',
            'content' => $x['content'] ?? '',
            'type'    => $x['type'] ?? 'sms',
            'cmd'     => $x['cmd'] ?? '',
        );
    }
    sms_ok('ok', array('items' => $items));
}

if ($act === 'done') {
    sms_auth(true);
    $id = req_body()['id'] ?? '';
    if ($id === '') sms_fail('缺少 id');
    outbox_done($id);
    sms_ok('ok');
}


if ($act === 'cmd_done') {
    sms_auth(true);
    $b = req_body();
    $id = $b['id'] ?? '';
    if ($id === '') sms_fail('缺少 id');
    outbox_cmd_done($id, $b['result'] ?? '');
    sms_ok('ok');
}

sms_fail('unknown action', 404);
