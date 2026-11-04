<?php
// Construct one private generation and publish both trees with one atomic rename.
declare(strict_types=1);

$runtime = '/opt/remote-runtime';
$root = '/var/www/localhost/htdocs/remote';
$stage = null;
$pending = null;
$manifest = null;

function discardOwned(string $path): void {
    if (is_link($path) || !is_dir($path)) {
        if (file_exists($path) || is_link($path)) { if (!unlink($path)) throw new RuntimeException("Cannot unlink $path"); }
        return;
    }
    foreach (new DirectoryIterator($path) as $item) {
        if (!$item->isDot()) discardOwned($item->getPathname());
    }
    if (!rmdir($path)) throw new RuntimeException("Cannot remove $path");
}

// Only regular files and directories enter the public generation. Never follow links.
function overlay(string $source, string $destination): void {
    if (is_link($source) || !is_dir($source)) return;
    foreach (new DirectoryIterator($source) as $item) {
        if ($item->isDot() || strcasecmp($item->getFilename(), '.htaccess') === 0) continue;
        $src = $item->getPathname();
        $dst = $destination . '/' . $item->getFilename();
        if (is_link($src)) continue;
        if ($item->isDir()) {
            if (is_link($dst) || (file_exists($dst) && !is_dir($dst))) throw new RuntimeException("Overlay type conflict: $dst");
            if (!is_dir($dst) && !mkdir($dst, 0755)) throw new RuntimeException("Cannot create $dst");
            overlay($src, $dst);
        } elseif ($item->isFile()) {
            if (is_link($dst) || is_dir($dst)) throw new RuntimeException("Overlay type conflict: $dst");
            if (!copy($src, $dst) || !chmod($dst, 0644)) throw new RuntimeException("Cannot copy $src");
        }
    }
}

function validateGenerated(string $path): void {
    if (is_link($path) || !is_dir($path)) throw new RuntimeException("Unsafe generated directory: $path");
    foreach (new DirectoryIterator($path) as $item) {
        if ($item->isDot()) continue;
        $p = $item->getPathname();
        if (is_link($p) || (!$item->isDir() && !$item->isFile()) || strcasecmp($item->getFilename(), '.htaccess') === 0) {
            throw new RuntimeException("Unsafe generated entry: $p");
        }
        if ($item->isDir()) validateGenerated($p);
        elseif (lstat($p)['nlink'] !== 1) throw new RuntimeException("Hard link in generation: $p");
    }
}

// Record every generated entry so a later startup deletes only an unchanged
// generation created here. Unknown or modified trees are left untouched.
function inventory(string $path, string $prefix = ''): array {
    $entries = [];
    foreach (new DirectoryIterator($path) as $item) {
        if ($item->isDot()) continue;
        $relative = $prefix . $item->getFilename();
        $full = $item->getPathname();
        if (is_link($full)) throw new RuntimeException("Symlink in generation: $full");
        if ($item->isDir()) {
            $entries['d:' . base64_encode($relative)] = '';
            $entries += inventory($full, $relative . '/');
        } elseif ($item->isFile()) {
            $hash = hash_file('sha256', $full);
            if ($hash === false) throw new RuntimeException("Cannot hash $full");
            $entries['f:' . base64_encode($relative)] = $hash;
        } else throw new RuntimeException("Unsafe generation entry: $full");
    }
    ksort($entries, SORT_STRING);
    return $entries;
}

try {
    if (is_link($runtime) || realpath($runtime) !== $runtime || !is_dir($runtime)) throw new RuntimeException('Unsafe runtime directory');
    if (is_link($runtime . '/.lock')) throw new RuntimeException('Unsafe runtime lock');
    $lock = fopen($runtime . '/.lock', 'c');
    if ($lock === false || !flock($lock, LOCK_EX)) throw new RuntimeException('Cannot lock runtime directory');
    foreach (['data', 'SystemEN'] as $name) {
        if (!is_link("$root/$name") || readlink("$root/$name") !== "$runtime/current/$name") throw new RuntimeException("Unsafe public path: $name");
    }
    $old = null;
    if (is_link("$runtime/current")) {
        $old = readlink("$runtime/current");
        if (!is_string($old) || !preg_match('/^generation-[a-f0-9]{24}$/D', $old) || is_link("$runtime/$old") || !is_dir("$runtime/$old")) {
            throw new RuntimeException('Unsafe current generation');
        }
    } elseif (file_exists("$runtime/current")) throw new RuntimeException('Unsafe current path');

    $id = bin2hex(random_bytes(12));
    $candidate = "$runtime/generation-$id";
    if (!mkdir($candidate, 0700)) throw new RuntimeException('Cannot create generation');
    $stage = $candidate;
    passthru('php /usr/local/bin/roenglish-generate.php /opt/translation ' . escapeshellarg($stage), $status);
    if ($status !== 0) throw new RuntimeException("ROEnglish generator failed ($status)");
    foreach (['data', 'SystemEN'] as $name) {
        validateGenerated("$stage/$name");
        overlay("/opt/remote-base/$name", "$stage/$name");
        overlay("/opt/client_files/$name", "$stage/$name");
    }
    $manifestPath = "$runtime/.manifest-$id";
    $record = json_encode(inventory($stage), JSON_THROW_ON_ERROR | JSON_INVALID_UTF8_SUBSTITUTE);
    $handle = fopen($manifestPath, 'x');
    if ($handle === false) throw new RuntimeException('Cannot create generation inventory');
    $manifest = $manifestPath;
    if (fwrite($handle, $record) !== strlen($record) || !fclose($handle)) throw new RuntimeException('Cannot save generation inventory');
    $candidate = "$runtime/.current-$id";
    if (!symlink("generation-$id", $candidate)) throw new RuntimeException('Cannot prepare publication');
    $pending = $candidate;
    if (!rename($pending, "$runtime/current")) throw new RuntimeException('Cannot publish generation');
    $pending = null;
    $stage = null;
    $manifest = null;
    if ($old !== null) {
        $oldManifest = "$runtime/.manifest-" . substr($old, strlen('generation-'));
        try {
            if (!is_link($oldManifest) && is_file($oldManifest) &&
                file_get_contents($oldManifest) === json_encode(inventory("$runtime/$old"), JSON_THROW_ON_ERROR | JSON_INVALID_UTF8_SUBSTITUTE)) {
                discardOwned("$runtime/$old");
                unlink($oldManifest);
            } else fwrite(STDERR, "Preserving modified or unverified generation $old\n");
        } catch (Throwable $cleanup) {
            fwrite(STDERR, "Preserving generation $old: " . $cleanup->getMessage() . "\n");
        }
    }
} catch (Throwable $e) {
    if ($pending !== null && is_link($pending)) unlink($pending);
    if ($manifest !== null && is_file($manifest) && !is_link($manifest)) unlink($manifest);
    if ($stage !== null && is_dir($stage) && !is_link($stage)) {
        try { discardOwned($stage); } catch (Throwable $cleanup) { fwrite(STDERR, $cleanup->getMessage() . "\n"); }
    }
    fwrite(STDERR, 'ROEnglish startup: ' . $e->getMessage() . "\n");
    exit(1);
}
