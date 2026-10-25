<?php
declare(strict_types=1);
namespace Campura\Camap;

final class Camap
{
    public const VERSION = "0.1.0",
        MAX_BYTES = 20971520,
        COLLECTIONS = ["frames", "features", "nodes", "edges"];
    public static function uuid(): string
    {
        $b = random_bytes(16);
        $b[6] = chr((ord($b[6]) & 15) | 64);
        $b[8] = chr((ord($b[8]) & 63) | 128);
        $h = bin2hex($b);
        return substr($h, 0, 8) .
            "-" .
            substr($h, 8, 4) .
            "-" .
            substr($h, 12, 4) .
            "-" .
            substr($h, 16, 4) .
            "-" .
            substr($h, 20);
    }
    public static function empty(string $title = "校园地图"): array
    {
        return [
            "formatVersion" => self::VERSION,
            "id" => self::uuid(),
            "title" => $title,
            "masterId" => null,
            "baseRevision" => null,
            "frames" => [],
            "features" => [],
            "nodes" => [],
            "edges" => [],
            "tombstones" => [],
        ];
    }
    public static function json(mixed $value): string
    {
        return json_encode(
            $value,
            JSON_UNESCAPED_UNICODE |
                JSON_UNESCAPED_SLASHES |
                JSON_UNESCAPED_LINE_TERMINATORS |
                JSON_THROW_ON_ERROR,
        );
    }
    public static function documentJSON(array $d): string
    {
        foreach ($d["frames"] as &$f) {
            $f["bindings"] = (object) $f["bindings"];
        }
        unset($f);
        return self::json($d);
    }
    private static function u16(string $b, int $p): int
    {
        return unpack("v", substr($b, $p, 2))[1];
    }
    private static function u32(string $b, int $p): int
    {
        return unpack("V", substr($b, $p, 4))[1];
    }
    private static function ensure(
        bool $ok,
        string $message = "Invalid CAMAP ZIP STORE package",
    ): void {
        if (!$ok) {
            throw new \InvalidArgumentException($message);
        }
    }
    public static function decode(string $bytes): array
    {
        $len = strlen($bytes);
        self::ensure($len >= 22 && $len <= self::MAX_BYTES);
        $e = $len - 22;
        self::ensure(
            self::u32($bytes, $e) === 0x06054b50 &&
                self::u16($bytes, $e + 4) === 0 &&
                self::u16($bytes, $e + 6) === 0 &&
                self::u16($bytes, $e + 20) === 0 &&
                self::u16($bytes, $e + 8) === 2 &&
                self::u16($bytes, $e + 10) === 2,
        );
        $start = self::u32($bytes, $e + 16);
        self::ensure($start + self::u32($bytes, $e + 12) === $e);
        $p = $start;
        $local = 0;
        $files = [];
        for ($i = 0; $i < 2; $i++) {
            self::ensure($p + 46 <= $e && self::u32($bytes, $p) === 0x02014b50);
            $n = self::u16($bytes, $p + 28);
            $size = self::u32($bytes, $p + 24);
            $off = self::u32($bytes, $p + 42);
            $crc = self::u32($bytes, $p + 16);
            self::ensure(
                self::u16($bytes, $p + 8) === 0 &&
                    self::u16($bytes, $p + 10) === 0 &&
                    self::u16($bytes, $p + 30) === 0 &&
                    self::u16($bytes, $p + 32) === 0 &&
                    self::u16($bytes, $p + 34) === 0 &&
                    $size === self::u32($bytes, $p + 20) &&
                    $off === $local &&
                    $p + 46 + $n <= $e,
            );
            $name = substr($bytes, $p + 46, $n);
            self::ensure(
                in_array($name, ["manifest.json", "document.json"], true) &&
                    !isset($files[$name]) &&
                    $off + 30 + $n + $size <= $start,
            );
            self::ensure(
                self::u32($bytes, $off) === 0x04034b50 &&
                    self::u16($bytes, $off + 6) === 0 &&
                    self::u16($bytes, $off + 8) === 0 &&
                    self::u16($bytes, $off + 26) === $n &&
                    self::u16($bytes, $off + 28) === 0 &&
                    self::u32($bytes, $off + 14) === $crc &&
                    self::u32($bytes, $off + 18) === $size &&
                    self::u32($bytes, $off + 22) === $size &&
                    substr($bytes, $off + 30, $n) === $name,
            );
            $data = substr($bytes, $off + 30 + $n, $size);
            self::ensure(crc32($data) === $crc);
            $files[$name] = $data;
            $local = $off + 30 + $n + $size;
            $p += 46 + $n;
        }
        self::ensure($p === $e && $local === $start);
        $m = json_decode(
            $files["manifest.json"],
            true,
            64,
            JSON_THROW_ON_ERROR,
        );
        self::ensure(
            ($m["format"] ?? null) === "camap" &&
                ($m["version"] ?? null) === self::VERSION &&
                ($m["document"] ?? null) === "document.json" &&
                hash_equals(
                    hash("sha256", $files["document.json"]),
                    (string) ($m["sha256"] ?? ""),
                ),
            "Unsupported format or checksum mismatch",
        );
        $d = json_decode(
            $files["document.json"],
            true,
            64,
            JSON_THROW_ON_ERROR,
        );
        self::validate($d);
        return $d;
    }
    public static function encode(array $document): string
    {
        self::validate($document);
        $data = self::documentJSON($document);
        $files = [
            "manifest.json" => self::json([
                "format" => "camap",
                "version" => self::VERSION,
                "document" => "document.json",
                "sha256" => hash("sha256", $data),
            ]),
            "document.json" => $data,
        ];
        $out = "";
        $central = "";
        foreach ($files as $name => $data) {
            $offset = strlen($out);
            $crc = crc32($data);
            $n = strlen($name);
            $size = strlen($data);
            $out .=
                pack(
                    "VvvvvvVVVvv",
                    0x04034b50,
                    20,
                    0,
                    0,
                    0,
                    0,
                    $crc,
                    $size,
                    $size,
                    $n,
                    0,
                ) .
                $name .
                $data;
            $central .=
                pack(
                    "VvvvvvvVVVvvvvvVV",
                    0x02014b50,
                    20,
                    20,
                    0,
                    0,
                    0,
                    0,
                    $crc,
                    $size,
                    $size,
                    $n,
                    0,
                    0,
                    0,
                    0,
                    0,
                    $offset,
                ) . $name;
        }
        $bytes =
            $out .
            $central .
            pack(
                "VvvvvVVv",
                0x06054b50,
                0,
                0,
                2,
                2,
                strlen($central),
                strlen($out),
                0,
            );
        self::ensure(strlen($bytes) <= self::MAX_BYTES, "Package too large");
        return $bytes;
    }
    public static function validate(mixed $d): void
    {
        self::ensure(
            is_array($d) && ($d["formatVersion"] ?? null) === self::VERSION,
            "Unsupported document",
        );
        $uuid = fn($s) => is_string($s) &&
            preg_match(
                '/^[a-f0-9]{8}-[a-f0-9]{4}-[1-8][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/iD',
                $s,
            );
        $point = fn($p) => is_array($p) &&
            array_is_list($p) &&
            count($p) === 2 &&
            is_numeric($p[0]) &&
            !is_string($p[0]) &&
            is_numeric($p[1]) &&
            !is_string($p[1]) &&
            is_finite((float) $p[0]) &&
            is_finite((float) $p[1]) &&
            abs($p[0]) <= 100000 &&
            abs($p[1]) <= 100000;
        self::ensure(
            $uuid($d["id"] ?? null) &&
                is_string($d["title"] ?? null) &&
                trim($d["title"]) !== "" &&
                strlen($d["title"]) <= 800,
            "Invalid document metadata",
        );
        self::ensure(
            array_key_exists("masterId", $d) &&
                array_key_exists("baseRevision", $d),
            "Missing provenance",
        );
        self::ensure(
            ($d["masterId"] === null && $d["baseRevision"] === null) ||
                ($uuid($d["masterId"]) &&
                    is_int($d["baseRevision"]) &&
                    $d["baseRevision"] >= 0),
            "Invalid provenance",
        );
        $maps = [];
        foreach (self::COLLECTIONS as $c) {
            self::ensure(
                isset($d[$c]) &&
                    is_array($d[$c]) &&
                    array_is_list($d[$c]) &&
                    count($d[$c]) <= 50000,
                "Invalid collection " . $c,
            );
            $maps[$c] = [];
            foreach ($d[$c] as $e) {
                self::ensure(
                    is_array($e) &&
                        $uuid($e["id"] ?? null) &&
                        !isset($maps[$c][$e["id"]]) &&
                        is_int($e["revision"] ?? null) &&
                        $e["revision"] >= 1,
                    "Invalid entity " . $c,
                );
                $maps[$c][$e["id"]] = $e;
            }
        }
        foreach ($d["frames"] as $f) {
            self::ensure(
                ($f["unit"] ?? null) === "m" &&
                    is_string($f["name"] ?? null) &&
                    isset($f["bindings"]) &&
                    is_array($f["bindings"]),
                "Invalid frame",
            );
            foreach ($f["bindings"] as $provider => $b) {
                self::ensure(
                    in_array($provider, ["amap", "mapkit"], true) &&
                        is_array($b) &&
                        is_numeric($b["longitude"] ?? null) &&
                        is_numeric($b["latitude"] ?? null) &&
                        is_numeric($b["rotation"] ?? null) &&
                        abs($b["longitude"]) <= 180 &&
                        abs($b["latitude"]) <= 80,
                    "Invalid calibration",
                );
            }
        }
        foreach ($d["features"] as $f) {
            $g = $f["geometry"] ?? [];
            $kind = $f["kind"] ?? "";
            self::ensure(
                isset($maps["frames"][$f["frameId"] ?? ""]) &&
                    in_array(
                        $kind,
                        [
                            "area",
                            "building",
                            "merchant",
                            "room",
                            "door",
                            "gate",
                            "stairs",
                            "elevator",
                            "poi",
                            "text",
                        ],
                        true,
                    ) &&
                    is_string($f["name"] ?? null),
                "Invalid feature",
            );
            self::ensure(
                in_array($g["type"] ?? "", ["point", "line", "polygon"], true),
                "Invalid geometry",
            );
            if ($g["type"] === "point") {
                self::ensure(
                    $point($g["coordinates"] ?? null),
                    "Invalid point",
                );
            } else {
                self::ensure(
                    is_array($g["coordinates"] ?? null) &&
                        count($g["coordinates"]) >=
                            ($g["type"] === "polygon" ? 3 : 2),
                    "Invalid polygon",
                );
                foreach ($g["coordinates"] as $p) {
                    self::ensure($point($p), "Invalid coordinate");
                }
            }
            $b = $maps["features"][$f["buildingId"] ?? ""] ?? null;
            if (isset($f["buildingId"])) {
                self::ensure(
                    $b !== null &&
                        $b["kind"] === "building" &&
                        $b["frameId"] === $f["frameId"],
                    "Invalid building reference",
                );
            }
            if (isset($f["parentId"])) {
                $p = $maps["features"][$f["parentId"]] ?? null;
                self::ensure(
                    $p !== null &&
                        $p["id"] !== $f["id"] &&
                        $p["frameId"] === $f["frameId"],
                    "Invalid parent reference",
                );
            }
            if (isset($f["levels"])) {
                self::ensure(
                    $kind === "building" && is_array($f["levels"]),
                    "Invalid building levels",
                );
                $ids = [];
                foreach ($f["levels"] as $l) {
                    self::ensure(
                        $uuid($l["id"] ?? null) &&
                            !isset($ids[$l["id"]]) &&
                            is_string($l["label"] ?? null) &&
                            is_numeric($l["ordinal"] ?? null),
                        "Invalid level",
                    );
                    $ids[$l["id"]] = true;
                }
            }
            $levels = array_column($b["levels"] ?? [], "id");
            if (isset($f["levelId"])) {
                self::ensure(
                    in_array($f["levelId"], $levels, true),
                    "Unknown level",
                );
            }
            if (isset($f["servedLevelIds"])) {
                self::ensure(
                    in_array($kind, ["stairs", "elevator"], true) &&
                        is_array($f["servedLevelIds"]) &&
                        !array_diff($f["servedLevelIds"], $levels),
                    "Unknown served level",
                );
            }
            foreach (["exterior", "accessible"] as $k) {
                if (isset($f[$k])) {
                    self::ensure(is_bool($f[$k]), "Invalid boolean");
                }
            }
            if (isset($f["width"])) {
                self::ensure(
                    is_numeric($f["width"]) &&
                        !is_string($f["width"]) &&
                        $f["width"] > 0,
                    "Invalid width",
                );
            }
        }
        foreach ($d["nodes"] as $n) {
            self::ensure(
                isset($maps["frames"][$n["frameId"] ?? ""]) &&
                    $point($n["position"] ?? null) &&
                    is_string($n["name"] ?? null),
                "Invalid route node",
            );
            if (isset($n["entranceId"])) {
                $f = $maps["features"][$n["entranceId"]] ?? null;
                self::ensure(
                    $f !== null &&
                        in_array($f["kind"], ["door", "gate"], true) &&
                        ($f["exterior"] ?? false) === true &&
                        $f["frameId"] === $n["frameId"] &&
                        $f["geometry"]["type"] === "point" &&
                        hypot(
                            $f["geometry"]["coordinates"][0] -
                                $n["position"][0],
                            $f["geometry"]["coordinates"][1] -
                                $n["position"][1],
                        ) <= 0.01,
                    "Route must terminate at an exterior entrance",
                );
            }
        }
        foreach ($d["edges"] as $e) {
            $a = $maps["nodes"][$e["from"] ?? ""] ?? null;
            $b = $maps["nodes"][$e["to"] ?? ""] ?? null;
            self::ensure(
                $a &&
                    $b &&
                    $a["id"] !== $b["id"] &&
                    $a["frameId"] === ($e["frameId"] ?? null) &&
                    $b["frameId"] === $e["frameId"] &&
                    is_array($e["points"] ?? null),
                "Invalid route edge",
            );
            foreach ($e["points"] as $p) {
                self::ensure($point($p), "Invalid route coordinate");
            }
            foreach (["oneWay", "accessible", "covered", "closed"] as $k) {
                self::ensure(
                    is_bool($e[$k] ?? null),
                    "Invalid route attribute",
                );
            }
        }
        self::ensure(
            is_array($d["tombstones"] ?? null) &&
                array_is_list($d["tombstones"]),
            "Invalid tombstones",
        );
        $seen = [];
        foreach ($d["tombstones"] as $t) {
            $key = ($t["collection"] ?? "") . ":" . ($t["id"] ?? "");
            self::ensure(
                in_array($t["collection"] ?? "", self::COLLECTIONS, true) &&
                    $uuid($t["id"] ?? null) &&
                    !isset($seen[$key]) &&
                    !isset($maps[$t["collection"]][$t["id"]]),
                "Invalid tombstone",
            );
            $seen[$key] = true;
        }
    }
    private static function canonical(mixed $v): mixed
    {
        if (!is_array($v)) {
            return $v;
        }
        if (!array_is_list($v)) {
            unset($v["revision"]);
            ksort($v);
        }
        foreach ($v as &$child) {
            $child = self::canonical($child);
        }
        return $v;
    }
    private static function same(mixed $a, mixed $b): bool
    {
        return self::json(self::canonical($a)) ===
            self::json(self::canonical($b));
    }
    public static function merge(
        ?array $base,
        array $server,
        array $incoming,
        array $resolutions = [],
    ): array {
        $document = $server;
        $conflicts = [];
        $duplicates = [];
        $unresolved = [];
        foreach (self::COLLECTIONS as $c) {
            $prior = array_column($base[$c] ?? [], null, "id");
            $current = array_column($server[$c], null, "id");
            $out = $current;
            $changes = array_column($incoming[$c], null, "id");
            foreach ($incoming["tombstones"] as $t) {
                if ($t["collection"] === $c) {
                    $changes[$t["id"]] = null;
                }
            }
            foreach ($changes as $id => $next) {
                $old = $prior[$id] ?? null;
                $now = $current[$id] ?? null;
                $key = $c . ":" . $id;
                $chosen = $now;
                if (self::same($now, $next) || self::same($old, $next)) {
                    continue;
                }
                if (self::same($old, $now)) {
                    $chosen = $next;
                } else {
                    $conflicts[] = [
                        "key" => $key,
                        "collection" => $c,
                        "id" => $id,
                        "base" => $old,
                        "server" => $now,
                        "incoming" => $next,
                    ];
                    $choice = $resolutions[$key] ?? null;
                    if ($choice === "incoming") {
                        $chosen = $next;
                    } elseif ($choice !== "server") {
                        $unresolved[] = $key;
                        continue;
                    }
                }
                if ($chosen !== null) {
                    $chosen["revision"] = ($now["revision"] ?? 0) + 1;
                    $out[$id] = $chosen;
                } else {
                    unset($out[$id]);
                }
                if (
                    $c === "features" &&
                    $old === null &&
                    $now === null &&
                    $chosen !== null
                ) {
                    $center = fn($f) => $f["geometry"]["type"] === "point"
                        ? $f["geometry"]["coordinates"]
                        : $f["geometry"]["coordinates"][0];
                    $a = $center($chosen);
                    foreach ($server["features"] as $s) {
                        $b = $center($s);
                        if (
                            $s["kind"] === $chosen["kind"] &&
                            $s["frameId"] === $chosen["frameId"] &&
                            ($s["levelId"] ?? null) ===
                                ($chosen["levelId"] ?? null) &&
                            hypot($a[0] - $b[0], $a[1] - $b[1]) < 2
                        ) {
                            $key = "duplicate:" . $id;
                            $duplicates[] = [
                                "key" => $key,
                                "incomingId" => $id,
                                "serverId" => $s["id"],
                            ];
                            if (($resolutions[$key] ?? null) === "drop") {
                                unset($out[$id]);
                            }
                            break;
                        }
                    }
                }
            }
            $document[$c] = array_values($out);
        }
        $document["tombstones"] = [];
        return compact("document", "conflicts", "duplicates", "unresolved");
    }
}
