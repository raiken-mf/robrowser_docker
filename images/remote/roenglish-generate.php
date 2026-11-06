<?php
/** Linux port of the pinned ClientGenerator; intentionally limited additions.
 * Addons are not installed. Navigation Legacy is also excluded: its packed
 * mob IDs and link-distance records do not match roBrowser consumers, and
 * replacing only part of the related tables can mix incompatible datasets.
 * Input must be trusted and must not be modified concurrently with generation.
 */
declare(strict_types=1);
function fail(string $message): never { throw new RuntimeException($message); }
function envValue(string $name, string $default, array $allowed): string {
    $v = getenv($name); $v = $v === false ? $default : $v;
    if (!in_array($v, $allowed, true)) fail("Invalid $name: $v");
    return $v;
}
function safeSource(string $path): void {
    global $source;
    if (!str_starts_with($path, $source . "/")) fail("Input outside source: $path");
    $part = $source;
    foreach (explode("/", substr($path, strlen($source) + 1)) as $name) {
        if ($name === "" || $name === "." || $name === "..") fail("Unsafe input path: $path");
        $part .= "/" . $name;
        if (is_link($part)) fail("Symlink in input: $part");
    }
}
function scanFiles(string $dir): array {
    safeSource($dir);
    if (is_link($dir) || !is_dir($dir)) fail("Not a real directory: $dir");
    $out = []; $names = scandir($dir, SCANDIR_SORT_ASCENDING);
    if ($names === false) fail("Cannot read directory: $dir");
    foreach ($names as $name) {
        if ($name === '.' || $name === '..') continue;
        $path = $dir . '/' . $name;
        if (is_link($path)) fail("Symlink in input: $path");
        if (is_dir($path)) {
            foreach (scanFiles($path) as $relative) $out[] = $name . '/' . $relative;
        } elseif (is_file($path)) $out[] = $name;
        else fail("Unsupported input entry: $path");
    }
    return $out;
}
function put(array &$files, string $source, string $target): void {
    safeSource($source);
    if (!is_file($source)) fail("Missing or unsafe input file: $source");
    // xcopy overwrites names case-insensitively. Retain the first target spelling.
    $key = strtolower($target);
    $files[$key] = [$source, $files[$key][1] ?? $target];
}
function layer(array &$files, string $dir): void {
    foreach (scanFiles($dir) as $p) {
        $first = explode('/', $p, 2)[0];
        if ($first !== 'data' && $first !== 'SystemEN') continue;
        put($files, $dir . '/' . $p, $p);
    }
}
function dropPrefix(array &$files, string $path): void {
    $key = strtolower($path);
    foreach (array_keys($files) as $k) if ($k === $key || str_starts_with($k, $key . '/')) unset($files[$k]);
}
try {
    if ($argc !== 3) fail('Usage: php roenglish-generate.php SOURCE_DIRECTORY EMPTY_TARGET_DIRECTORY');
    $source = realpath($argv[1]); $target = realpath($argv[2]);
    if ($source === false || !is_dir($source) || is_link($argv[1])) fail('Source must be an existing real directory');
    if ($target === false || !is_dir($target) || is_link($argv[2])) fail('Target must be an existing real directory');
    if ($source === $target || str_starts_with($target . '/', $source . '/') || str_starts_with($source . '/', $target . '/')) fail('Source and target must not overlap');
    if (count(scandir($target)) !== 2) fail('Target must be empty');
    $date = getenv('PACKETVER'); $date = $date === false ? '20211103' : $date;
    if (!preg_match('/^[0-9]{8}$/D', $date) || !checkdate((int)substr($date,4,2), (int)substr($date,6,2), (int)substr($date,0,4))) fail('PACKETVER must be a valid YYYYMMDD date');
    $mode = envValue('SET_PRERENEWAL', '0', ['0','1']);
    envValue('ROENGLISH_ADDITIONS', 'all', ['all']);
    envValue('ROENGLISH_ADDONS', 'compatible', ['compatible']);
    $legacy = envValue('ROENGLISH_LEGACY_MAPS', '0', ['0','1']);
    $dates = ['2012-04-10','2015-05-13','2015-10-29','2017-06-14','2017-12-13','2018-06-20','2019-06-05','2020-09-02','2021-10-28','2022-03-30','2022-04-06','2022-06-02','2022-08-31','2022-09-28','2022-12-07','2023-01-18','2023-08-02','2023-09-20','2024-03-11','2024-04-03','2024-05-02','2024-08-07','2024-10-16','2025-01-22','2025-06-18','2025-09-02','2025-12-17'];
    $index = 0;
    foreach ($dates as $i => $d) if (str_replace('-', '', $d) <= $date) $index = $i + 1;
    if ($index === 0) fail('PACKETVER predates the first generator date');
    if ($index === 1 && $mode === '0') fail('The 2012 generator selection is Pre-Renewal only');
    if ($date > '20251217') fwrite(STDERR, "Warning: PACKETVER is newer than the last generator selection; using 2025-12-17.\n");
    $files = [];
    layer($files, "$source/Translation/Renewal");
    if ($mode === '1') layer($files, "$source/Translation/Pre-Renewal");
    $selectedMode = $mode === '1' ? 'Pre-Renewal' : 'Renewal';
    $copyDate = function(string $d) use (&$files, $source, $selectedMode): void {
        $root = "$source/Translation/Compatibility/$d";
        if (is_link($root) || is_link("$root/$selectedMode")) fail("Symlink in compatibility path: $root");
        layer($files, is_dir("$root/$selectedMode") ? "$root/$selectedMode" : $root);
    };
    if ($index <= 2) $copyDate($dates[$index - 1]);
    if ($index !== 3) {
        for ($counter = 5; $counter <= $index; $counter++) $copyDate($dates[$counter - 2]);
        $copyDate($dates[$index - 1]);
        if ($index >= 19) dropPrefix($files, 'data/luafiles514/lua files/hateffectinfo');
        if ($index >= 25) dropPrefix($files, 'data/luafiles514/lua files/selectpackage/selectpackageitem.lub');
    }
    // Only all-in-one selections with matching roBrowser loaders are copied.
    $add = "$source/Additions";
    foreach (['PetEvolution.lub','CheckAttendance.lub','PrivateAirplane.lub'] as $name) {
        put($files, "$add/SystemEN/$name", "SystemEN/$name");
    }
    foreach (['mp3nametable.txt','resnametable.txt','num2cardillustnametable.txt','buyingstoreitemlist.txt','cardpostfixnametable.txt','indoorrswtable.txt'] as $name) put($files, "$add/data/$name", "data/$name");
    // The browser requests this exact lowercase URL. Apache may serve the
    // loose file directly, without RemoteClient's case-insensitive lookup.
    $fog = 'data/fogparametertable.txt';
    put($files, "$add/data/fogParameterTable.txt", $fog);
    $files[$fog][1] = $fog;
    $lua = 'data/luafiles514/lua files/';
    foreach (['accessoryid.lub','accname.lub','spriterobeid.lub','spriterobename.lub','weapontable.lub','tb_cashshop_banner.lub','npcidentity.lub','jobname.lub'] as $name) {
        $p = $lua . 'datainfo/' . $name; put($files, "$add/$p", $p);
    }
    // Paired with Translation/Renewal's addrandomoptionnametable.lub.
    $p = $lua . 'datainfo/enumvar.lub'; put($files, "$add/$p", $p);
    // These all-in-one files depend on the remaining files from the base
    // translation or client GRF (stateiconinfo, worldview language/list).
    foreach (['stateicon/efstids.lub','stateicon/stateiconimginfo.lub','worldviewdata/worldviewdata_table.lub'] as $name) {
        $p = $lua . $name; put($files, "$add/$p", $p);
    }
    if ($date >= '20211028') { $p = $lua . 'ItemDBNameTbl.lub'; put($files, "$add/$p", $p); }
    if ($legacy === '1') {
        // The two all-in-one menu choices: root maps and their explicit BMPs,
        // followed by the separately enumerated legacy minimaps.
        foreach (scanFiles("$add/data") as $p) {
            if (!str_contains($p, '/') && preg_match('/\.(gat|gnd|rsw)$/iD', $p)) put($files, "$add/data/$p", "data/$p");
            $maps = ['2009rwc_01','2009rwc_02','2009rwc_03','2009rwc_04','2009rwc_05','2009rwc_06','2009rwc_07','2009rwc_08','2009rwc_f01','poring_c01','poring_c02','payon','ama_dun01','ayo_dun01','ice_dun04','map2_int','new_zone02','new_zone04','ra_temsky','tha_t07','tha_t08','thana_boss','tur_dun05','tur_dun06','yggdrasil01','yuno_in02'];
            if (preg_match('~^texture/[^/]+/map/([^/]+)\.bmp$~iD', $p, $m) && in_array(strtolower($m[1]), $maps, true)) put($files, "$add/data/$p", "data/$p");
        }
    }
    ksort($files, SORT_STRING);
    foreach (['data','SystemEN'] as $dir) if (!mkdir("$target/$dir", 0755)) fail("Cannot create $dir");
    foreach ($files as [$src, $rel]) {
        $dest = "$target/$rel"; $parent = dirname($dest);
        if (!is_dir($parent) && !mkdir($parent, 0755, true) && !is_dir($parent)) fail("Cannot create $parent");
        $in = fopen($src, 'rb'); $out = fopen($dest, 'xb');
        if ($in === false || $out === false) fail("Cannot copy $rel");
        if (stream_copy_to_stream($in, $out) === false || !fclose($out)) fail("Cannot write $rel");
        fclose($in); chmod($dest, 0644);
    }
    fwrite(STDOUT, "Generated " . count($files) . " files; generator selection {$dates[$index-1]} ($selectedMode).\n");
} catch (Throwable $e) { fwrite(STDERR, 'Error: ' . $e->getMessage() . "\n"); exit(1); }
