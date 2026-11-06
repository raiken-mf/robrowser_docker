<?php
declare(strict_types=1);
$generator = realpath(__DIR__ . '/../images/remote/roenglish-generate.php');
$root = sys_get_temp_dir() . '/roenglish-fixture-' . bin2hex(random_bytes(8));
function fixture(string $path, string $content): void { if (!is_dir(dirname($path))) mkdir(dirname($path), 0777, true); file_put_contents($path, $content); }
function check(bool $ok, string $message): void { if (!$ok) throw new RuntimeException($message); }
function erase(string $path): void { if (is_link($path) || is_file($path)) { unlink($path); return; } foreach (scandir($path) as $n) if ($n !== '.' && $n !== '..') erase("$path/$n"); rmdir($path); }
function snapshot(string $dir): array {
    $result = []; $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS));
    foreach ($it as $file) if ($file->isFile()) $result[substr($file->getPathname(), strlen($dir) + 1)] = hash_file('sha256', $file->getPathname());
    ksort($result); return $result;
}
function runGenerator(string $source, string $target, array $env): array {
    global $generator;
    $cmd = [PHP_BINARY, $generator, $source, $target];
    $vars = array_merge($_ENV, ['PACKETVER'=>'20211103','SET_PRERENEWAL'=>'0','ROENGLISH_ADDITIONS'=>'all','ROENGLISH_ADDONS'=>'compatible','ROENGLISH_LEGACY_MAPS'=>'0'], $env);
    $p = proc_open($cmd, [0=>['pipe','r'],1=>['pipe','w'],2=>['pipe','w']], $pipes, null, $vars);
    check(is_resource($p), 'proc_open failed'); fclose($pipes[0]); $out = stream_get_contents($pipes[1]); fclose($pipes[1]); $err = stream_get_contents($pipes[2]); fclose($pipes[2]);
    return [proc_close($p), $out, $err];
}
try {
    mkdir($root); $src = "$root/source"; $dst = "$root/target"; mkdir($dst);
    fixture("$src/Translation/Renewal/data/base.txt", 'renewal'); fixture("$src/Translation/Renewal/SystemEN/base.lub", 'system');
    fixture("$src/Translation/Pre-Renewal/data/base.txt", 'pre');
    $dates = ['2012-04-10','2015-05-13','2017-06-14','2017-12-13','2018-06-20','2019-06-05','2020-09-02','2021-10-28','2022-03-30','2022-04-06','2022-06-02','2022-08-31','2022-09-28','2022-12-07','2023-01-18','2023-08-02','2023-09-20','2024-03-11','2024-04-03','2024-05-02','2024-08-07','2024-10-16','2025-01-22','2025-06-18','2025-09-02','2025-12-17'];
    foreach ($dates as $d) fixture("$src/Translation/Compatibility/$d/data/markers/$d", $d);
    fixture("$src/Translation/Compatibility/2018-06-20/Renewal/data/mode.txt", 're'); fixture("$src/Translation/Compatibility/2018-06-20/Pre-Renewal/data/mode.txt", 'pre-mode');
    fixture("$src/Translation/Renewal/data/luafiles514/lua files/hateffectinfo/remove.lub", 'old');
    fixture("$src/Translation/Renewal/data/luafiles514/lua files/selectpackage/selectpackageitem.lub", 'old');
    fixture("$src/Additions/SystemEN/PetEvolution.lub", 'pet');
    fixture("$src/Additions/SystemEN/CheckAttendance.lub", 'attendance');
    fixture("$src/Additions/SystemEN/PrivateAirplane.lub", 'airship');
    foreach (['mp3nametable.txt','resnametable.txt','num2cardillustnametable.txt','buyingstoreitemlist.txt','cardpostfixnametable.txt','indoorrswtable.txt','fogParameterTable.txt'] as $n) fixture("$src/Additions/data/$n", $n);
    foreach (['stateicon/efstids.lub','stateicon/stateiconimginfo.lub','worldviewdata/worldviewdata_table.lub'] as $n) fixture("$src/Additions/data/luafiles514/lua files/$n", $n);
    $lua = 'data/luafiles514/lua files';
    foreach (['accessoryid','accname','spriterobeid','spriterobename','weapontable','tb_cashshop_banner','npcidentity','jobname'] as $n) fixture("$src/Additions/$lua/datainfo/$n.lub", $n);
    fixture("$src/Translation/Renewal/$lua/datainfo/addrandomoptionnametable.lub", 'random-options');
    fixture("$src/Translation/Renewal/$lua/datainfo/enumvar.lub", 'base-enum');
    fixture("$src/Additions/$lua/datainfo/enumvar.lub", 'additions-enum');
    fixture("$src/Additions/$lua/ItemDBNameTbl.lub", 'item'); fixture("$src/Additions/data/example.gat", 'map');
    fixture("$src/Additions/data/texture/legacy/map/payon.bmp", 'map-bmp'); fixture("$src/Additions/data/texture/legacy/map/sch_lab.bmp", 'excluded');
    fixture("$src/Additions/data/texture/legacy/map/ama_dun01.bmp", 'minimap');
    // Navigation Legacy is a related dataset, not six independent overrides.
    // A packed Ghoul class and distance tuple from the pinned source illustrate
    // the mismatches with the current search and path-finder consumers.
    $navNames = ['map', 'mob', 'npc', 'link', 'linkdistance', 'npcdistance'];
    foreach ($navNames as $name) {
        $file = "navi_{$name}_krpri.lub";
        fixture("$src/Addons/Navigation Legacy/$file", "addon-$name");
        fixture("$src/Translation/Pre-Renewal/$lua/navigation/$file", "pre-$name");
    }
    $packedGhoul = 3736588;
    check($packedGhoul !== 1036 && ($packedGhoul & 0xffff) === 1036, 'packed mob fixture');
    $distance = ['E', 13429, 678];
    check($distance[0] !== 'abbey02' && $distance[1] !== 1, 'distance tuple fixture');
    [$status] = runGenerator($src, $dst, ['PACKETVER'=>'20151029']);
    check($status === 0, 'navigation renewal fixture');
    foreach ($navNames as $name) check(!file_exists("$dst/$lua/navigation/navi_{$name}_krpri.lub"), "unsafe navigation addon $name");
    erase($dst); mkdir($dst);
    [$status] = runGenerator($src, $dst, ['PACKETVER'=>'20151029', 'SET_PRERENEWAL'=>'1']);
    check($status === 0, 'navigation pre-renewal fixture');
    foreach ($navNames as $name) check(file_get_contents("$dst/$lua/navigation/navi_{$name}_krpri.lub") === "pre-$name", "navigation priority $name");
    erase($dst); mkdir($dst);
    // Exercise every official date and the day before the next selection.
    $menu = ['2012-04-10','2015-05-13','2015-10-29','2017-06-14','2017-12-13','2018-06-20','2019-06-05','2020-09-02','2021-10-28','2022-03-30','2022-04-06','2022-06-02','2022-08-31','2022-09-28','2022-12-07','2023-01-18','2023-08-02','2023-09-20','2024-03-11','2024-04-03','2024-05-02','2024-08-07','2024-10-16','2025-01-22','2025-06-18','2025-09-02','2025-12-17'];
    foreach ($menu as $i => $selected) {
        $samples = [str_replace('-', '', $selected)];
        if (isset($menu[$i + 1])) $samples[] = (new DateTimeImmutable($menu[$i + 1]))->modify('-1 day')->format('Ymd');
        foreach ($samples as $sample) {
            [$status, $out] = runGenerator($src, $dst, ['PACKETVER'=>$sample, 'SET_PRERENEWAL'=>'1']);
            check($status === 0 && str_contains($out, "selection $selected "), "date mapping $sample");
            check(file_get_contents("$dst/$lua/datainfo/enumvar.lub") === 'additions-enum' && file_get_contents("$dst/$lua/datainfo/addrandomoptionnametable.lub") === 'random-options', "random option pair $sample");
            if ($i !== 2 && $selected !== '2018-06-20') check(is_file("$dst/data/markers/$selected"), "selected overlay $sample");
            $expectedPrevious = $i >= 4;
            check(is_file("$dst/data/markers/2017-06-14") === ($i === 3 || $expectedPrevious), "loop start $sample");
            erase($dst); mkdir($dst);
        }
    }
    foreach (['20211027'=>false, '20211028'=>true] as $threshold => $present) {
        [$status] = runGenerator($src, $dst, ['PACKETVER'=>(string)$threshold]);
        check($status === 0 && is_file("$dst/$lua/ItemDBNameTbl.lub") === $present, "item threshold $threshold");
        erase($dst); mkdir($dst);
    }
    [$code] = runGenerator($src, $dst, ['PACKETVER'=>'20171212','SET_PRERENEWAL'=>'1']);
    check($code === 0, '2017 generation failed'); check(file_get_contents("$dst/data/base.txt") === 'pre', 'pre layer');
    check(is_file("$dst/data/markers/2017-06-14"), 'selected date missing'); check(!file_exists("$dst/data/markers/2017-12-13"), 'future date included');
    check(!file_exists("$dst/$lua/ItemDBNameTbl.lub"), 'early item table'); check(!file_exists("$dst/data/example.gat"), 'legacy disabled');
    erase($dst); mkdir($dst);
    [$code] = runGenerator($src, $dst, ['PACKETVER'=>'20180620','SET_PRERENEWAL'=>'1']);
    check($code === 0, '2018 generation failed'); check(file_get_contents("$dst/data/mode.txt") === 'pre-mode', 'mode-specific overlay');
    check(is_file("$dst/data/markers/2017-06-14") && is_file("$dst/data/markers/2017-12-13"), 'index-shifted loop');
    erase($dst); mkdir($dst);
    [$code] = runGenerator($src, $dst, ['PACKETVER'=>'20250618','ROENGLISH_LEGACY_MAPS'=>'1']);
    check($code === 0, '2025 generation failed'); check(!file_exists("$dst/$lua/hateffectinfo/remove.lub"), 'hat effect deletion');
    check(!file_exists("$dst/$lua/selectpackage/selectpackageitem.lub"), 'select package deletion');
    check(is_file("$dst/$lua/ItemDBNameTbl.lub"), 'item table threshold'); check(is_file("$dst/data/example.gat"), 'legacy map');
    check(is_file("$dst/data/texture/legacy/map/ama_dun01.bmp") && !file_exists("$dst/data/texture/legacy/map/sch_lab.bmp"), 'explicit minimaps');
    foreach (['mp3nametable.txt','resnametable.txt','num2cardillustnametable.txt','buyingstoreitemlist.txt','cardpostfixnametable.txt','indoorrswtable.txt'] as $n) check(file_get_contents("$dst/data/$n") === $n, "text table $n");
    check(file_get_contents("$dst/data/fogparametertable.txt") === 'fogParameterTable.txt', 'lowercase fog path without base file');
    check(!file_exists("$dst/data/fogParameterTable.txt"), 'mixed-case fog path');
    foreach (['stateicon/efstids.lub','stateicon/stateiconimginfo.lub','worldviewdata/worldviewdata_table.lub','datainfo/tb_cashshop_banner.lub'] as $n) check(is_file("$dst/$lua/$n"), "lua addition $n");
    $first = snapshot($dst); $other = "$root/other"; mkdir($other);
    [$status] = runGenerator($src, $other, ['PACKETVER'=>'20250618','ROENGLISH_LEGACY_MAPS'=>'1']);
    check($status === 0 && $first === snapshot($other), 'non-reproducible output');
    fixture("$src/Translation/Renewal/data/FogParameterTable.txt", 'old fog');
    erase($other); mkdir($other);
    [$status] = runGenerator($src, $other, ['PACKETVER'=>'20250618']);
    check($status === 0 && file_get_contents("$other/data/fogparametertable.txt") === 'fogParameterTable.txt' && !file_exists("$other/data/FogParameterTable.txt"), 'lowercase fog path overrides mixed-case base');
    [$code] = runGenerator($src, $dst, []); check($code !== 0 && is_file("$dst/data/example.gat"), 'nonempty target accepted');
    erase($dst); mkdir($dst);
    foreach ([['PACKETVER'=>'20120409'], ['PACKETVER'=>'20120410'], ['PACKETVER'=>'20230230'], ['ROENGLISH_ADDONS'=>'all'], ['ROENGLISH_LEGACY_MAPS'=>'yes']] as $env) {
        [$code] = runGenerator($src, $dst, $env); check($code !== 0 && count(scandir($dst)) === 2, 'invalid input accepted or wrote target');
    }
    [$code, , $err] = runGenerator($src, $dst, ['PACKETVER'=>'20260101']); check($code === 0 && str_contains($err, 'Warning:'), 'future warning');
    erase($dst); mkdir($dst); symlink('/etc/passwd', "$src/Translation/Renewal/data/escape");
    [$code] = runGenerator($src, $dst, []); check($code !== 0 && count(scandir($dst)) === 2, 'symlink accepted');
    echo "PASS: generator fixtures\n";
} finally { if (is_dir($root)) erase($root); }
