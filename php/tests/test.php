<?php
declare(strict_types=1);
require_once __DIR__ . "/../src/Camap.php";
use Campura\Camap\Camap;
$assertions = 0;
function check(bool $ok, string $message): void
{
    global $assertions;
    if (!$ok) {
        throw new RuntimeException($message);
    }
    $assertions++;
}
$bytes = file_get_contents(__DIR__ . "/fixtures/demo.camap");
$d = Camap::decode($bytes);
check(Camap::decode(Camap::encode($d)) === $d, "roundtrip");
$bad = $bytes;
$bad[100] = chr(ord($bad[100]) ^ 1);
try {
    Camap::decode($bad);
    throw new RuntimeException("accepted corruption");
} catch (InvalidArgumentException) {
    $assertions++;
}
$server = $d;
$incoming = $d;
$server["features"][0]["name"] = "A";
$incoming["features"][0]["name"] = "B";
$r = Camap::merge($d, $server, $incoming);
check(count($r["unresolved"]) === 1, "concurrent edit conflict");
$r = Camap::merge($d, $server, $incoming, [$r["unresolved"][0] => "incoming"]);
check($r["document"]["features"][0]["name"] === "B", "resolution");
$server = $d;
$incoming = $d;
$server["features"][0]["name"] = "01";
$incoming["features"][0]["name"] = "1";
check(
    count(Camap::merge($d, $server, $incoming)["unresolved"]) === 1,
    "numeric strings differ",
);
$incoming = $d;
$incoming["features"] = [$d["features"][0]];
check(
    count(Camap::merge($d, $d, $incoming)["document"]["features"]) === 5,
    "omitted is not deleted",
);
$badDoc = $d;
$badDoc["nodes"] = [];
try {
    Camap::validate($badDoc);
    throw new RuntimeException("accepted dangling edges");
} catch (InvalidArgumentException) {
    $assertions++;
}
if (isset($argv[1])) {
    file_put_contents($argv[1], Camap::encode($d));
}
echo "$assertions PHP assertions passed.\n";
