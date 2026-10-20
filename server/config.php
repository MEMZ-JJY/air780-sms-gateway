<?php



define('SMS_TOKEN', 'CHANGE_ME');


define('SMS_ENABLE_TOKEN', true);

define('LOG_FILE',      __DIR__ . '/sms.log');
define('OUTBOX_FILE',   __DIR__ . '/outbox.json');
define('MAX_OUTBOX',    50);      
define('KEEP_SENT',     200);






define('STATUS_FILE',    __DIR__ . '/status.json');     


function sms_json($arr, $code = 200)
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Headers: *');
    echo json_encode($arr, JSON_UNESCAPED_UNICODE);
    exit;
}
function sms_ok($msg = 'ok', $extra = array())
{
    sms_json(array_merge(array('ok' => true, 'msg' => $msg), $extra));
}
function sms_fail($msg, $code = 400)
{
    sms_json(array('ok' => false, 'msg' => $msg), $code);
}


function sms_auth($require_token_token = false)
{
    $t = null;
    if (isset($_GET['token'])) {
        $t = $_GET['token'];
    } elseif (isset($_SERVER['CONTENT_TYPE']) && strpos($_SERVER['CONTENT_TYPE'], 'json') !== false) {
        $raw = file_get_contents('php://input');
        $d = json_decode($raw, true);
        if (is_array($d) && isset($d['token'])) {
            $t = $d['token'];
        }
    } else {
        $raw = file_get_contents('php://input');
        $d = json_decode($raw, true);
        if (is_array($d) && isset($d['token'])) {
            $t = $d['token'];
        }
    }
    $need = $require_token_token && SMS_ENABLE_TOKEN;
    if ($need && $t !== SMS_TOKEN) {
        sms_fail('forbidden', 403);
    }
    return true;
}


function sms_lock_read()
{
    if (!file_exists(LOG_FILE)) {
        return '';
    }
    $fp = fopen(LOG_FILE, 'c+');
    if (!$fp) return '';
    flock($fp, LOCK_SH);
    $s = stream_get_contents($fp);
    flock($fp, LOCK_UN);
    fclose($fp);
    return $s;
}

function sms_split($raw)
{
    $raw = preg_replace("/\r\n/", "\n", $raw);
    return preg_split('/(?=\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} \| )/', $raw, -1, PREG_SPLIT_NO_EMPTY);
}


function sms_read_items()
{
    $blocks = sms_split(sms_lock_read());
    $out = array();
    foreach ($blocks as $idx => $b) {
        $b = trim($b);
        if ($b === '') continue;
        $p = explode(' | ', $b, 4);
        if (count($p) < 3) continue;
        if (count($p) === 4) {
            $time = $p[0]; $type = $p[1]; $from = $p[2]; $content = $p[3];
        } else {
            $time = $p[0]; $type = 'sms'; $from = $p[1]; $content = $p[2];
        }
        $out[] = array(
            'idx'     => $idx,
            'time'    => $time,
            'type'    => in_array($type, array('sms', 'call', 'msg')) ? $type : 'sms',
            'from'    => $from,
            'content' => trim($content),
        );
    }
    return $out;
}

function sms_write_line($type, $from, $content)
{
    $line = date('Y-m-d H:i:s') . ' | ' . $type . ' | ' . $from . ' | ' . $content . "\n";
    $fp = fopen(LOG_FILE, 'a+');
    if (!$fp) return false;
    flock($fp, LOCK_EX);
    fseek($fp, 0, SEEK_END);
    $raw = stream_get_contents($fp);
    
    $blocks = sms_split($raw);
    $last = trim(end($blocks));
    if ($last === trim($line)) {
        flock($fp, LOCK_UN);
        fclose($fp);
        return 'dup';
    }
    fwrite($fp, $line);
    fflush($fp);
    flock($fp, LOCK_UN);
    fclose($fp);
    return 'ok';
}


function sms_write_blocks($blocks)
{
    $tmp = LOG_FILE . '.tmp';
    $fp = fopen($tmp, 'w+');
    if (!$fp) return false;
    flock($fp, LOCK_EX);
    foreach ($blocks as $b) {
        fwrite($fp, $b . "\n");
    }
    fflush($fp);
    flock($fp, LOCK_UN);
    fclose($fp);
    @chmod($tmp, 0644);
    @rename($tmp, LOG_FILE);
    return true;
}



define('CACHE_FILE', __DIR__ . '/latest.cache');
define('CACHE_TTL',   2);        

function sms_cache_get($key)
{
    if (!file_exists(CACHE_FILE)) return null;
    if (time() - filemtime(CACHE_FILE) > CACHE_TTL) return null;
    $fp = @fopen(CACHE_FILE, 'c+');
    if (!$fp) return null;
    flock($fp, LOCK_SH);
    $s = trim(stream_get_contents($fp));
    flock($fp, LOCK_UN);
    fclose($fp);
    if ($s === '') return null;
    $all = json_decode($s, true);
    return (is_array($all) && isset($all[$key])) ? $all[$key] : null;
}

function sms_cache_set($key, $val)
{
    $fp = @fopen(CACHE_FILE, 'c+');
    if (!$fp) return false;
    flock($fp, LOCK_EX);
    $s = trim(stream_get_contents($fp));
    $all = ($s === '') ? array() : (json_decode($s, true) ?: array());
    $all[$key] = $val;
    ftruncate($fp, 0);
    fseek($fp, 0);
    fwrite($fp, json_encode($all, JSON_UNESCAPED_UNICODE));
    fflush($fp);
    flock($fp, LOCK_UN);
    fclose($fp);
    @chmod(CACHE_FILE, 0644);
    return true;
}


function outbox_read()
{
    if (!file_exists(OUTBOX_FILE)) return array();
    $fp = fopen(OUTBOX_FILE, 'c+');
    if (!$fp) return array();
    flock($fp, LOCK_SH);
    $s = stream_get_contents($fp);
    flock($fp, LOCK_UN);
    fclose($fp);
    $s = trim($s);
    if ($s === '') return array();
    $d = json_decode($s, true);
    return is_array($d) ? $d : array();
}

function outbox_write($arr)
{
    $tmp = OUTBOX_FILE . '.tmp';
    $fp = fopen($tmp, 'w+');
    if (!$fp) return false;
    flock($fp, LOCK_EX);
    fwrite($fp, json_encode($arr, JSON_UNESCAPED_UNICODE));
    fflush($fp);
    flock($fp, LOCK_UN);
    fclose($fp);
    @chmod($tmp, 0644);
    @rename($tmp, OUTBOX_FILE);
    return true;
}

function outbox_push($num, $content)
{
    $arr = outbox_read();
    $id = date('YmdHi') . '_' . strtoupper(substr(md5($num . $content . microtime(true)), 0, 6));
    $arr[] = array('id' => $id, 'num' => $num, 'content' => $content, 'ts' => date('Y-m-d H:i:s'), 'status' => 'pending');
    if (count($arr) > MAX_OUTBOX) {
        $arr = array_slice($arr, -MAX_OUTBOX);
    }
    outbox_write($arr);
    return $id;
}


function outbox_push_cmd($cmd)
{
    $arr = outbox_read();
    $id = date('YmdHi') . '_' . strtoupper(substr(md5($cmd . microtime(true)), 0, 6));
    $arr[] = array('id' => $id, 'type' => 'cmd', 'cmd' => $cmd, 'ts' => date('Y-m-d H:i:s'), 'status' => 'pending');
    if (count($arr) > MAX_OUTBOX) {
        $arr = array_slice($arr, -MAX_OUTBOX);
    }
    outbox_write($arr);
    return $id;
}


function outbox_cmd_done($id, $result = '')
{
    $arr = outbox_read();
    $hit = false;
    foreach ($arr as &$x) {
        if (($x['id'] ?? '') === $id) {
            $x['status']    = 'done';
            $x['done_ts']   = date('Y-m-d H:i:s');
            $x['result']    = is_string($result) ? $result : (string)$result;
            $hit = true;
            break;
        }
    }
    unset($x);
    if (!$hit) return false;
    if (count($arr) > KEEP_SENT) {
        $arr = array_slice($arr, -KEEP_SENT);
    }
    outbox_write($arr);
    return true;
}


function outbox_take()
{
    $arr = outbox_read();
    if (!$arr) return array();
    
    $out = array();
    foreach ($arr as &$x) {
        $st = $x['status'] ?? 'pending';
        
        if ($st === 'sent' || $st === 'done') {
            continue;
        }
        if ($st === 'pending') {
            $x['status'] = 'inflight';
        }
        $out[] = $x;
    }
    unset($x);
    outbox_write($arr);
    return $out;
}


function outbox_done($id)
{
    $arr = outbox_read();
    $hit = false;
    foreach ($arr as &$x) {
        if (($x['id'] ?? '') === $id) {
            $x['status']  = 'sent';
            $x['sent_ts'] = date('Y-m-d H:i:s');
            $hit = true;
            break;
        }
    }
    unset($x);
    if (!$hit) return false;
    if (count($arr) > KEEP_SENT) {
        $arr = array_slice($arr, -KEEP_SENT);
    }
    outbox_write($arr);
    return true;
}

function outbox_remove($id)
{
    $arr = outbox_read();
    $arr = array_values(array_filter($arr, function ($x) use ($id) {
        return ($x['id'] ?? '') !== $id;
    }));
    outbox_write($arr);
    return true;
}
