<?php
declare(strict_types=1);
namespace Campura\Camap;

/** Outdoor routing on published CAMAP edges. All lengths are local frame metres. */
final class Routing
{
    public array $nodes = [], $edges = [], $features = [], $frames = [], $unsafeEdges = [];
    private array $adj = [], $buildingCells = [], $largeBuildings = [], $unsafeSet = [];
    public function __construct(public readonly array $document)
    {
        Camap::validate($document);
        foreach (['nodes', 'edges', 'features', 'frames'] as $collection) {
            foreach ($document[$collection] as $item) $this->{$collection}[$item['id']] = $item;
        }
        foreach ($this->features as $id=>$f) {
            if ($f['kind']!=='building' || $f['geometry']['type']!=='polygon') continue;
            $cells=$this->cells($f['geometry']['coordinates']);
            if ($cells===null) $this->largeBuildings[$f['frameId']][]=$id;
            else foreach ($cells as $cell) $this->buildingCells[$f['frameId']][$cell][]=$id;
        }
        foreach ($this->edges as $id => $e) {
            $points = [$this->nodes[$e['from']]['position'], ...$e['points'], $this->nodes[$e['to']]['position']];
            $length = self::length($points);
            $this->edges[$id]['polyline'] = $points;
            $this->edges[$id]['length'] = $length;
            if ($this->crossesBuilding($points, $e['frameId'])) { $this->unsafeEdges[] = $id; $this->unsafeSet[$id]=true; }
            $this->adj[$e['from']][] = [$e['to'], $id, false];
            if (!$e['oneWay']) $this->adj[$e['to']][] = [$e['from'], $id, true];
        }
    }
    public static function length(array $points): float
    {
        $sum = 0.;
        for ($i=1; $i<count($points); $i++) $sum += hypot($points[$i][0]-$points[$i-1][0], $points[$i][1]-$points[$i-1][1]);
        return $sum;
    }
    public static function pointSegment(array $p, array $a, array $b): float
    {
        $dx=$b[0]-$a[0]; $dy=$b[1]-$a[1]; $d=$dx*$dx+$dy*$dy;
        $t=$d>0 ? max(0., min(1., (($p[0]-$a[0])*$dx+($p[1]-$a[1])*$dy)/$d)) : 0.;
        return hypot($p[0]-$a[0]-$t*$dx, $p[1]-$a[1]-$t*$dy);
    }
    public static function inside(array $p, array $polygon): bool
    {
        $hit=false; $n=count($polygon);
        for ($i=0,$j=$n-1; $i<$n; $j=$i++) {
            $a=$polygon[$j]; $b=$polygon[$i];
            if (self::pointSegment($p,$a,$b)<0.001) return false; // boundary is not interior
            if (($a[1]>$p[1])!==($b[1]>$p[1]) && $p[0]<($b[0]-$a[0])*($p[1]-$a[1])/($b[1]-$a[1])+$a[0]) $hit=!$hit;
        }
        return $hit;
    }
    private static function intersectionParameter(array $a,array $b,array $c,array $d): ?float
    {
        $rx=$b[0]-$a[0]; $ry=$b[1]-$a[1]; $sx=$d[0]-$c[0]; $sy=$d[1]-$c[1];
        $den=$rx*$sy-$ry*$sx;
        if (abs($den)<1e-9) return null;
        $t=(($c[0]-$a[0])*$sy-($c[1]-$a[1])*$sx)/$den;
        $u=(($c[0]-$a[0])*$ry-($c[1]-$a[1])*$rx)/$den;
        return $t>=0 && $t<=1 && $u>=0 && $u<=1 ? $t : null;
    }
    public static function segmentInterior(array $a,array $b,array $polygon): bool
    {
        $cuts=[0.,1.];
        foreach ($polygon as $i=>$c) {
            $t=self::intersectionParameter($a,$b,$c,$polygon[($i+1)%count($polygon)]);
            if ($t!==null) $cuts[]=$t;
        }
        sort($cuts);
        for ($i=1;$i<count($cuts);$i++) {
            $t=($cuts[$i-1]+$cuts[$i])/2;
            if (self::inside([$a[0]+($b[0]-$a[0])*$t,$a[1]+($b[1]-$a[1])*$t],$polygon)) return true;
        }
        return false;
    }
    private function cells(array $points): ?array
    {
        $xs=array_column($points,0);$ys=array_column($points,1);
        $x0=(int)floor(min($xs)/50);$x1=(int)floor(max($xs)/50);$y0=(int)floor(min($ys)/50);$y1=(int)floor(max($ys)/50);
        if (($x1-$x0+1)*($y1-$y0+1)>1024) return null;
        $cells=[];for($x=$x0;$x<=$x1;$x++)for($y=$y0;$y<=$y1;$y++)$cells[]=$x.':'.$y;return $cells;
    }
    public function crossesBuilding(array $points,string $frame): bool
    {
        for ($i=1;$i<count($points);$i++) {
            $cells=$this->cells([$points[$i-1],$points[$i]]);
            $ids=$this->largeBuildings[$frame] ?? [];
            if ($cells===null) { foreach ($this->features as $id=>$f) if ($f['frameId']===$frame && $f['kind']==='building' && $f['geometry']['type']==='polygon') $ids[]=$id; }
            else foreach ($cells as $cell) array_push($ids,...($this->buildingCells[$frame][$cell] ?? []));
            foreach (array_unique($ids) as $id) if (self::segmentInterior($points[$i-1],$points[$i],$this->features[$id]['geometry']['coordinates'])) return true;
        }
        return false;
    }
    public function nearFeatureEdges(string $featureID,float $radius=15.): array
    {
        $f=$this->features[$featureID] ?? null; if (!$f) return [];
        $g=$f['geometry']; $points=$g['type']==='point' ? [$g['coordinates']] : $g['coordinates'];
        if ($g['type']==='polygon') $points[]=$points[0];
        $ids=[];
        foreach ($this->edges as $id=>$e) {
            if ($e['frameId']!==$f['frameId']) continue;
            $line=$e['polyline']; $distance=INF;
            foreach ($line as $p) {
                if ($g['type']==='polygon' && self::inside($p,$g['coordinates'])) $distance=0.;
                if (count($points)===1) $distance=min($distance,hypot($p[0]-$points[0][0],$p[1]-$points[0][1]));
                for ($i=1;$i<count($points);$i++) $distance=min($distance,self::pointSegment($p,$points[$i-1],$points[$i]));
            }
            foreach ($points as $p) for ($i=1;$i<count($line);$i++) $distance=min($distance,self::pointSegment($p,$line[$i-1],$line[$i]));
            if ($g['type']==='polygon') for ($i=1;$i<count($line);$i++) if (self::segmentInterior($line[$i-1],$line[$i],$g['coordinates'])) $distance=0.;
            if ($distance<=$radius) $ids[]=$id;
        }
        return $ids;
    }
    /** Match exact stable IDs or names/aliases; ambiguous labels are returned to the caller. */
    public function places(string $query): array
    {
        if (isset($this->features[$query])) return [$this->features[$query]];
        if (isset($this->nodes[$query])) return [['id'=>$query,'name'=>$this->nodes[$query]['name'],'kind'=>'node','frameId'=>$this->nodes[$query]['frameId']]];
        $needle=mb_strtolower(trim($query)); $matches=[];
        if ($needle==='') return [];
        foreach ($this->features as $f) {
            if (!in_array($f['kind'],['building','room','merchant','poi','gate','door'],true)) continue;
            foreach ([$f['name'],...($f['aliases'] ?? [])] as $name) if (mb_strtolower(trim($name))===$needle) { $matches[]=$f; break; }
        }
        return $matches;
    }
    public function placeNodes(string $id,bool $accessible=false): array
    {
        if (isset($this->nodes[$id])) return [$id];
        $f=$this->features[$id] ?? null; if (!$f) return [];
        if ($f['kind']==='room') return $this->placeNodes($f['buildingId'] ?? '',$accessible);
        if ($f['kind']==='poi' && $f['geometry']['type']==='point') return array_values(array_keys(array_filter($this->nodes,fn($n)=>$n['frameId']===$f['frameId'] && hypot($n['position'][0]-$f['geometry']['coordinates'][0],$n['position'][1]-$f['geometry']['coordinates'][1])<=0.01)));
        $entrances=[];
        if (in_array($f['kind'],['door','gate'],true)) {
            if ($f['kind']==='door' && !($f['exterior'] ?? false)) return [];
            if (!$accessible || ($f['accessible'] ?? false)) $entrances[]=$id;
        } else {
            foreach ($this->features as $e) if (in_array($e['kind'],['door','gate'],true) && (($e['parentId'] ?? '')===$id || ($f['kind']==='building' && ($e['buildingId'] ?? '')===$id))
                && ($e['kind']==='gate' || ($e['exterior'] ?? false)) && (!$accessible || ($e['accessible'] ?? false))) $entrances[]=$e['id'];
            // A merchant nested in a building can use the building's published exterior entrance.
            if (!$entrances && isset($f['buildingId'])) return $this->placeNodes($f['buildingId'],$accessible);
        }
        return array_values(array_keys(array_filter($this->nodes,fn($n)=>in_array($n['entranceId'] ?? '',$entrances,true))));
    }
    /** Provider bindings must be explicitly present. Never rename GCJ-02 to MapKit. */
    public function localPosition(array $origin): array
    {
        $frame=$this->frames[$origin['frameId'] ?? ''] ?? null;
        if (!$frame) throw new \InvalidArgumentException('unknown frameId');
        if (isset($origin['position'])) $point=$origin['position'];
        else {
            $provider=$origin['provider'] ?? ''; $binding=$frame['bindings'][$provider] ?? null;
            if (!in_array($provider,['amap','mapkit'],true) || !$binding) throw new \InvalidArgumentException('provider binding unavailable');
            $lng=$origin['longitude'] ?? null; $lat=$origin['latitude'] ?? null;
            if (!is_numeric($lng) || !is_numeric($lat) || abs((float)$lat)>85 || abs((float)$lng)>180) throw new \InvalidArgumentException('invalid geographic position');
            $D=M_PI/180; $R=6378137.; $c=cos($binding['latitude']*$D);
            $east=($lng-$binding['longitude'])*$D*$R*$c;
            $north=(log(tan(M_PI/4+$lat*$D/2))-log(tan(M_PI/4+$binding['latitude']*$D/2)))*$R*$c;
            $r=$binding['rotation']*$D;
            $point=[$east*cos($r)+$north*sin($r),-$east*sin($r)+$north*cos($r)];
        }
        if (!is_array($point) || count($point)!==2 || !is_numeric($point[0]) || !is_numeric($point[1]) || !is_finite((float)$point[0]) || !is_finite((float)$point[1]) || hypot((float)$point[0],(float)$point[1])>10000) throw new \InvalidArgumentException('invalid local position');
        return [(float)$point[0],(float)$point[1]];
    }
    public function locate(array $origin): ?array
    {
        if (isset($origin['nodeID'])) {
            $n=$this->nodes[$origin['nodeID']] ?? null;
            return $n ? ['nodeID'=>$n['id'],'frameId'=>$n['frameId'],'position'=>$n['position'],'connectorMeters'=>0.] : null;
        }
        if (!is_numeric($origin['accuracyMeters'] ?? null) || $origin['accuracyMeters']<0 || $origin['accuracyMeters']>30) return null;
        $p=$this->localPosition($origin); $best=null; $distance=min(15.,max(3.,(float)$origin['accuracyMeters']));
        foreach ($this->edges as $id=>$e) {
            if ($e['frameId']!==$origin['frameId'] || $e['closed'] || isset($this->unsafeSet[$id])) continue;
            $line=$e['polyline'];$prefix=0.;
            for ($i=1;$i<count($line);$i++) {
                $a=$line[$i-1];$b=$line[$i];$dx=$b[0]-$a[0];$dy=$b[1]-$a[1];$length=hypot($dx,$dy);
                $t=$length>0?max(0.,min(1.,(($p[0]-$a[0])*$dx+($p[1]-$a[1])*$dy)/($length*$length))):0.;
                $q=[$a[0]+$t*$dx,$a[1]+$t*$dy];$gap=hypot($p[0]-$q[0],$p[1]-$q[1]);
                if ($gap<$distance && !$this->crossesBuilding([$p,$q],$origin['frameId'])) {
                    $distance=$gap;$offset=$prefix+$t*$length;
                    $best=['nodeID'=>$e['from'],'frameId'=>$e['frameId'],'position'=>$q,'observedPosition'=>$p,'accuracyMeters'=>(float)$origin['accuracyMeters'],'snapDistanceMeters'=>$gap,'snapEdgeID'=>$id,'connectorMeters'=>0.,'starts'=>[['nodeID'=>$e['to'],'distanceMeters'=>$e['length']-$offset,'polyline'=>[$q,...array_slice($line,$i)]]]];
                    if (!$e['oneWay']) $best['starts'][]=['nodeID'=>$e['from'],'distanceMeters'=>$offset,'polyline'=>array_reverse([...array_slice($line,0,$i),$q])];
                    if ($offset<0.01 || $e['length']-$offset<0.01) {
                        $node=$offset<0.01?$e['from']:$e['to'];
                        $best=['nodeID'=>$node,'frameId'=>$e['frameId'],'position'=>$this->nodes[$node]['position'],'observedPosition'=>$p,'accuracyMeters'=>(float)$origin['accuracyMeters'],'snapDistanceMeters'=>$gap,'connectorMeters'=>0.];
                    }
                }
                $prefix+=$length;
            }
        }
        return $best;
    }
    public function findRoute(string $from,string $to,array $options=[]): ?array
    {
        if (!isset($this->nodes[$from],$this->nodes[$to]) || $this->nodes[$from]['frameId']!==$this->nodes[$to]['frameId']) return null;
        $blocked=array_fill_keys([...($options['blockedEdges'] ?? []),...$this->unsafeEdges],true);
        $entrances=array_fill_keys($options['blockedEntrances'] ?? [],true);
        foreach ([$from,$to] as $node) if (isset($entrances[$this->nodes[$node]['entranceId'] ?? ''])) return null;
        $avoid=array_fill_keys($options['avoidEdges'] ?? [],true);
        $costs=[$from=>0.]; $previous=[]; $queue=new \SplPriorityQueue();
        $queue->setExtractFlags(\SplPriorityQueue::EXTR_BOTH); $queue->insert($from,0.);
        while (!$queue->isEmpty()) {
            $top=$queue->extract(); $u=$top['data']; $cost=-$top['priority'];
            if ($cost>$costs[$u]+1e-8) continue;
            if ($u===$to) break;
            foreach ($this->adj[$u] ?? [] as [$v,$id,$reverse]) {
                $e=$this->edges[$id];
                if ($e['closed'] || isset($blocked[$id]) || isset($entrances[$this->nodes[$v]['entranceId'] ?? '']) || (($options['accessible'] ?? false) && !$e['accessible'])) continue;
                $weight=$e['length']*(($options['preferCovered'] ?? false) && !$e['covered'] ? 1.3 : 1.) + (isset($avoid[$id]) ? 100000. : 0.);
                $next=$cost+$weight;
                if ($next<($costs[$v] ?? INF)) { $costs[$v]=$next; $previous[$v]=[$u,$id,$reverse]; $queue->insert($v,-$next); }
            }
        }
        if (!isset($costs[$to])) return null;
        $nodes=[$to]; $edges=[]; $lines=[]; $at=$to;
        while ($at!==$from) { [$u,$id,$reverse]=$previous[$at]; array_unshift($nodes,$u); array_unshift($edges,$id); array_unshift($lines,$reverse ? array_reverse($this->edges[$id]['polyline']) : $this->edges[$id]['polyline']); $at=$u; }
        $polyline=[$this->nodes[$from]['position']];
        foreach ($lines as $line) array_push($polyline,...array_slice($line,1));
        return ['nodes'=>$nodes,'edges'=>$edges,'frameId'=>$this->nodes[$from]['frameId'],'polyline'=>$polyline,'distanceMeters'=>array_sum(array_map(fn($id)=>$this->edges[$id]['length'],$edges)),'cost'=>$costs[$to]];
    }
    /** Dynamic programming over entrance alternatives preserves waypoint order. */
    public function itinerary(array $origin,array $stops,array $options=[]): ?array
    {
        $states=[];
        if (isset($origin['snapEdgeID'])) {
            $edge=$this->edges[$origin['snapEdgeID']];
            if (in_array($edge['id'],$options['blockedEdges'] ?? [],true) || (($options['accessible'] ?? false) && !$edge['accessible'])) return null;
            foreach ($origin['starts'] as $start) {
                if (in_array($this->nodes[$start['nodeID']]['entranceId'] ?? '',$options['blockedEntrances'] ?? [],true)) continue;
                $cost=$start['distanceMeters']*(($options['preferCovered'] ?? false) && !$edge['covered']?1.3:1.)+(in_array($edge['id'],$options['avoidEdges'] ?? [],true)?100000.:0.);
                $leg=['nodes'=>[$start['nodeID']],'edges'=>[$edge['id']],'polyline'=>$start['polyline'],'frameId'=>$edge['frameId'],'distanceMeters'=>$start['distanceMeters'],'cost'=>$cost];
                $states[$start['nodeID']]=['legs'=>[$leg],'cost'=>$cost,'distanceMeters'=>$start['distanceMeters']];
            }
        } else $states[$origin['nodeID']]=['legs'=>[],'cost'=>0.,'distanceMeters'=>$origin['connectorMeters']];
        if (!$states) return null;
        foreach ($stops as $stop) {
            $next=[];
            foreach ($this->placeNodes($stop['placeID'],$options['accessible'] ?? false) as $target) foreach ($states as $from=>$state) {
                $leg=$this->findRoute($from,$target,$options); if (!$leg) continue;
                $cost=$state['cost']+$leg['cost'];
                if (!isset($next[$target]) || $cost<$next[$target]['cost']) $next[$target]=['legs'=>[...$state['legs'],$leg],'cost'=>$cost,'distanceMeters'=>$state['distanceMeters']+$leg['distanceMeters']];
            }
            $states=$next; if (!$states) return null;
        }
        uasort($states,fn($a,$b)=>$a['cost']<=>$b['cost']); $best=reset($states);
        $best['origin']=array_intersect_key($origin,array_flip(['frameId','position','observedPosition','accuracyMeters','snapDistanceMeters']));
        $best['frameId']=$origin['frameId']; $best['polyline']=[$origin['position']]; $best['edges']=[];
        foreach ($best['legs'] as $leg) { array_push($best['polyline'],...$leg['polyline']); array_push($best['edges'],...$leg['edges']); }
        unset($best['cost']); return $best;
    }
}
