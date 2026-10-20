<?php

require __DIR__ . '/config.php';

header('Content-Type: text/html; charset=utf-8');

$items = sms_read_items();
$last  = end($items);                       

$content = $last ? $last['content'] : '暂无短信';
$from    = $last ? $last['from']    : '';
$time    = $last ? $last['time']    : '';

$e = function ($s) { return htmlspecialchars((string)$s, ENT_QUOTES, 'UTF-8'); };


$hour = (int)gmdate('G') + 8;
if ($hour >= 24) { $hour -= 24; }
$dark = ($hour >= 19 || $hour < 7);
$bg   = $dark ? '#1e1e1e' : '#ffffff';
$fg   = $dark ? '#e6e6e6' : '#222222';
$fg2  = $dark ? '#9a9a9a' : '#666666';   
?>
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">
<html lang="zh-CN">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<title>最新短信</title>
</head>
<body style="margin:0;padding:1em;background:<?php echo $bg; ?>;color:<?php echo $fg; ?>;">
<h1 style="margin:0 0 .4em;font-size:1.2em;"><?php echo $e($content); ?></h1>
<p style="margin:0;font-size:.9em;color:<?php echo $fg2; ?>"><?php echo $e(($from !== '' ? $from : '设备') . ($time !== '' ? '  ' . $time : '')); ?></p>
</body>
</html>
