<?php

require __DIR__ . '/config.php';

$act = $_GET['action'] ?? '';

function req_body()
{
    $d = json_decode(file_get_contents('php://input'), true);
    return is_array($d) ? $d : array();
}


if (!function_exists('mb_strlen')) {
    function mb_strlen($s)
    {
        return preg_match_all('/./us', (string)$s) ?: 0;
    }
}


if ($act === 'latest') {
    $n     = isset($_GET['n']) ? max(1, min(200, intval($_GET['n']))) : 20;
    $order = (isset($_GET['order']) && $_GET['order'] === 'asc') ? 'asc' : 'desc';
    $since = trim((string)($_GET['since'] ?? ''));

    $key   = "latest|{$n}|{$order}|{$since}";
    $hit   = sms_cache_get($key);
    if ($hit !== null) {
        sms_ok('ok', $hit);
    }

    $items = sms_read_items();

    
    if ($since !== '') {
        $items = array_values(array_filter($items, function ($x) use ($since) {
            return strcmp($x['time'], $since) > 0;
        }));
    }
    if (count($items) > $n) {
        $items = $order === 'asc'
            ? array_slice($items, 0, $n)
            : array_slice($items, -$n);
    }
    if ($order === 'desc') {
        $items = array_reverse($items);
    }
    $items = array_values($items);

    $payload = array(
        'count' => count($items),
        'items' => $items,
    );
    sms_cache_set($key, $payload);
    sms_ok('ok', $payload);
}

if ($act === 'list') {
    sms_auth(true);
    $items  = sms_read_items();
    $outbox = outbox_read();
    sms_ok('ok', array('items' => $items, 'outbox' => $outbox));
}

if ($act === 'del') {
    sms_auth(true);
    $idx = intval($_GET['idx'] ?? -1);
    if ($idx < 0) sms_fail('缺少 idx');
    $blocks = sms_split(sms_lock_read());
    if (!isset($blocks[$idx])) sms_fail('记录不存在');
    unset($blocks[$idx]);
    sms_write_blocks($blocks);
    sms_ok('已删除');
}

if ($act === 'del_thread' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    sms_auth(true);
    $from = req_body()['from'] ?? null;
    $blocks = sms_split(sms_lock_read());
    $left = array();
    foreach ($blocks as $i => $b) {
        $p = explode(' | ', trim($b), 4);
        $cur = (count($p) === 4) ? $p[2] : $p[1];
        if ($from !== null && $cur === $from) continue;
        $left[] = $b;
    }
    sms_write_blocks($left);
    sms_ok('会话已删除');
}

if ($act === 'clear') {
    sms_auth(true);
    sms_write_blocks(array());
    sms_ok('已清空');
}

if ($act === 'send' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    sms_auth(true);
    $b = req_body();
    $num = trim((string)($b['num'] ?? ''));
    $txt = trim((string)($b['content'] ?? ''));
    if ($num === '') sms_fail('缺少接收号码');
    if (mb_strlen($txt, 'UTF-8') < 1) sms_fail('短信内容为空');
    if (mb_strlen($txt, 'UTF-8') > 490) sms_fail('内容过长（最多约 490 字，按 70 字/条计费请自行拆分）');
    $id = outbox_push($num, $txt);
    sms_ok('已入队，等待模块取件', array('id' => $id));
}


if ($act === 'cmd' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    sms_auth(true);
    $b = req_body();
    $cmd = trim((string)($b['cmd'] ?? ''));
    if ($cmd === '') sms_fail('缺少 cmd');
    if (strpos($cmd, '##') !== 0) $cmd = '##' . $cmd;   
    $id = outbox_push_cmd($cmd);
    sms_ok('指令已下发，模块将在 60 秒内执行', array('id' => $id));
}

if ($act === 'outbox_del' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    sms_auth(true);
    $id = req_body()['id'] ?? '';
    if ($id === '') sms_fail('缺少 id');
    outbox_remove($id);
    sms_ok('已移除');
}

if ($act === 'outbox_done' && $_SERVER['REQUEST_METHOD'] === 'POST') {
    sms_auth(true);
    $id = req_body()['id'] ?? '';
    if ($id === '') sms_fail('缺少 id');
    outbox_done($id);
    sms_ok('已记录回执');
}


sms_fail('unknown action: ' . $act, 400);
