<?php
declare(strict_types=1);
namespace Campura\Camap;

/** Local, bounded road preparation. No provider access and no image/model calls. */
final class NetworkPreparation
{
    public const VERSION='network-preparation-1';
    public static function digest(mixed $value): string { return hash('sha256',Camap::json($value)); }
    private static function id(string $seed): string {
        $h=hash('sha256',self::VERSION.'|'.$seed);
        return substr($h,0,8).'-'.substr($h,8,4).'-4'.substr($h,13,3).'-a'.substr($h,17,3).'-'.substr($h,20,12);
    }
    private static function need(bool $ok,string $message): void { if (!$ok) throw new \InvalidArgumentException($message); }
    private static function point(mixed $p): array {
        self::need(is_array($p) && array_is_list($p) && count($p)===2,'invalid local point');
        foreach ($p as $n) self::need((is_int($n) || is_float($n)) && is_finite((float)$n) && abs($n)<=10000,'invalid local coordinate');
        return [(float)$p[0],(float)$p[1]];
    }
    private static function text(mixed $s,int $length=200): string {
        self::need(is_string($s) && trim($s)!=='' && mb_strlen($s)<=$length,'invalid source text');return trim($s);
    }
    private static function cross(array $a,array $b,array $c): float { return ($b[0]-$a[0])*($c[1]-$a[1])-($b[1]-$a[1])*($c[0]-$a[0]); }
    private static function touches(array $a,array $b,array $c,array $d): bool {
        if (min($a[0],$b[0])>max($c[0],$d[0])+1e-7 || min($c[0],$d[0])>max($a[0],$b[0])+1e-7 || min($a[1],$b[1])>max($c[1],$d[1])+1e-7 || min($c[1],$d[1])>max($a[1],$b[1])+1e-7) return false;
        return self::cross($a,$b,$c)*self::cross($a,$b,$d)<=1e-8 && self::cross($c,$d,$a)*self::cross($c,$d,$b)<=1e-8;
    }
    private static function polygon(array $points): array {
        self::need(array_is_list($points) && count($points)>=3 && count($points)<=100,'invalid area polygon');
        $p=array_map(self::point(...),$points);$area=0.;$n=count($p);
        for($i=0;$i<$n;$i++) {
            $a=$p[$i];$b=$p[($i+1)%$n];self::need(hypot($a[0]-$b[0],$a[1]-$b[1])>0.001,'degenerate polygon');$area+=$a[0]*$b[1]-$b[0]*$a[1];
            for($j=$i+1;$j<$n;$j++) if ($j!==$i+1 && !($i===0 && $j===$n-1)) self::need(!self::touches($a,$b,$p[$j],$p[($j+1)%$n]),'self-intersecting polygon');
        }
        self::need(abs($area)>0.01,'zero area polygon');return $p;
    }
    private static function contains(array $p,array $poly): bool {
        if (Routing::inside($p,$poly)) return true;
        foreach($poly as $i=>$a) if(Routing::pointSegment($p,$a,$poly[($i+1)%count($poly)])<1e-6) return true;
        return false;
    }
    /** Exact interval coverage of a segment by a union of surveyed polygons, not sampling. */
    private static function covered(array $a,array $b,array $areas): bool {
        if (!$areas) return false;$cuts=[0.,1.];$dx=$b[0]-$a[0];$dy=$b[1]-$a[1];$len=$dx*$dx+$dy*$dy;
        foreach($areas as $poly) foreach($poly as $i=>$c) {
            $d=$poly[($i+1)%count($poly)];$sx=$d[0]-$c[0];$sy=$d[1]-$c[1];$den=$dx*$sy-$dy*$sx;
            if(abs($den)>1e-9) {
                $t=(($c[0]-$a[0])*$sy-($c[1]-$a[1])*$sx)/$den;$u=(($c[0]-$a[0])*$dy-($c[1]-$a[1])*$dx)/$den;
                if($t>=0 && $t<=1 && $u>=0 && $u<=1)$cuts[]=$t;
            } elseif($len>1e-10 && abs(self::cross($a,$b,$c))<1e-7) foreach([$c,$d] as $p)$cuts[]=max(0.,min(1.,(($p[0]-$a[0])*$dx+($p[1]-$a[1])*$dy)/$len));
        }
        sort($cuts);
        foreach($cuts as $i=>$t) {
            $q=$i?($t+$cuts[$i-1])/2:$t;$p=[$a[0]+$q*$dx,$a[1]+$q*$dy];$ok=false;
            foreach($areas as $poly)if(self::contains($p,$poly)){$ok=true;break;}
            if(!$ok)return false;
        }
        foreach([$a,$b] as $p){$ok=false;foreach($areas as $poly)if(self::contains($p,$poly)){$ok=true;break;}if(!$ok)return false;}
        return true;
    }
    private static function blocked(array $line,string $frame,Routing $map,array $obstacles): bool {
        if ($map->crossesBuilding($line,$frame)) return true;
        foreach($obstacles as $o) {
            if($o['frameId']!==$frame)continue;$points=$o['coordinates'];$poly=$o['type']==='polygon';
            foreach($line as $p)if($poly && self::contains($p,$points))return true;
            if($poly)$points[]=$points[0];
            for($i=1;$i<count($line);$i++)for($j=1;$j<count($points);$j++)if(self::touches($line[$i-1],$line[$i],$points[$j-1],$points[$j]))return true;
        }
        return false;
    }
    private static function verified(array $line,string $frame,array $areas,bool $accessible=false): bool {
        $polys=array_column(array_filter($areas,fn($a)=>$a['frameId']===$frame && (!$accessible || $a['accessible'])),'coordinates');
        for($i=1;$i<count($line);$i++)if(!self::covered($line[$i-1],$line[$i],$polys))return false;
        return (bool)$polys;
    }
    /** A one-metre bounded grid only inside positively surveyed walkable ground. */
    private static function detour(array $a,array $b,string $frame,Routing $map,array $areas,array $obstacles,float $limit,int &$searchBudget): ?array {
        if(!self::verified([$a,$a],$frame,$areas) || !self::verified([$b,$b],$frame,$areas))return null;
        $radius=(int)ceil($limit);$heap=new \SplPriorityQueue();$heap->setExtractFlags(\SplPriorityQueue::EXTR_DATA);$heap->insert([0,0],0.);$dist=['0:0'=>0.];$previous=[];$visited=[];$count=0;
        while(!$heap->isEmpty() && ++$count<=8000){
            if(--$searchBudget<0)return null;
            [$x,$y]=$heap->extract();$key=$x.':'.$y;if(isset($visited[$key]))continue;$visited[$key]=true;$p=[$a[0]+$x,$a[1]+$y];$cost=$dist[$key];
            if(hypot($p[0]-$b[0],$p[1]-$b[1])<=1.5 && $cost+hypot($p[0]-$b[0],$p[1]-$b[1])<=$limit && !self::blocked([$p,$b],$frame,$map,$obstacles) && self::verified([$p,$b],$frame,$areas)){
                $line=[$b,$p];while(isset($previous[$key])){[$key,$pos]=$previous[$key];$line[]=$pos;} $line=array_reverse($line);$out=[$line[0]];
                // Simplify only after the same coverage and obstacle checks.
                for($i=1;$i<count($line);){$j=count($line)-1;for(;$j>$i;$j--)if(!self::blocked([end($out),$line[$j]],$frame,$map,$obstacles) && self::verified([end($out),$line[$j]],$frame,$areas))break;$out[]=$line[$j];$i=$j+1;}
                return $out;
            }
            foreach([[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]] as [$dx,$dy]){
                $nx=$x+$dx;$ny=$y+$dy;$nk=$nx.':'.$ny;if(abs($nx)>$radius || abs($ny)>$radius || isset($visited[$nk]))continue;
                $q=[$a[0]+$nx,$a[1]+$ny];$nc=$cost+hypot($dx,$dy);if($nc+hypot($q[0]-$b[0],$q[1]-$b[1])>$limit || $nc>=($dist[$nk] ?? INF))continue;
                if(self::blocked([$p,$q],$frame,$map,$obstacles) || !self::verified([$p,$q],$frame,$areas))continue;
                $dist[$nk]=$nc;$previous[$nk]=[$key,$p];$heap->insert([$nx,$ny],-($nc+hypot($q[0]-$b[0],$q[1]-$b[1])));
            }
        }
        return null;
    }
    public static function sourceStatus(): array { return ['basemap'=>['status'=>'not_configured','provider'=>null],'vision'=>['status'=>'not_configured','model'=>null]]; }
    /** Strict normalized provider boundary: local metres, explicit calibration, no URL fetching. */
    public static function normalizeSource(array $doc,?array $source): array {
        if($source===null)return ['nodes'=>[],'edges'=>[],'areas'=>[],'obstacles'=>[],'provenance'=>null];
        self::need(!array_diff(array_keys($source),['sourceID','version','kind','frameId','frameHash','accuracyMeters','groundVerified','nodes','edges','walkableAreas','obstacles']),'unknown source fields');
        $id=self::text($source['sourceID'] ?? null,80);$version=self::text($source['version'] ?? null,80);
        self::need(in_array($source['kind'] ?? null,['school_survey','manual','licensed_vector'],true),'source kind unavailable; vision is not configured');
        $frames=array_column($doc['frames'],null,'id');$frame=$source['frameId'] ?? '';self::need(isset($frames[$frame]),'unknown source frame');
        self::need(($source['frameHash'] ?? '')===self::digest($frames[$frame]),'source frame alignment changed');
        self::need(is_numeric($source['accuracyMeters'] ?? null) && $source['accuracyMeters']>=0 && $source['accuracyMeters']<=30,'invalid source accuracy');
        self::need(($source['groundVerified'] ?? false)===true,'source must verify outdoor ground topology; bridges and floors require separate mapping');
        $out=['nodes'=>[],'edges'=>[],'areas'=>[],'obstacles'=>[],'provenance'=>['sourceID'=>$id,'version'=>$version,'kind'=>$source['kind'],'frameId'=>$frame,'frameHash'=>$source['frameHash'],'accuracyMeters'=>(float)$source['accuracyMeters']]];
        foreach(['nodes','edges','walkableAreas','obstacles'] as $key){$v=$source[$key] ?? [];self::need(is_array($v) && array_is_list($v) && count($v)<=($key==='nodes'||$key==='edges'?500:50),'invalid or oversized source '.$key);}
        foreach($source['nodes'] ?? [] as $n){self::need(is_array($n) && ($n['frameId'] ?? '')===$frame && !isset($n['entranceId']),'invalid source node');$n['position']=self::point($n['position'] ?? null);$out['nodes'][]=$n;}
        $nodes=array_column([...$doc['nodes'],...$out['nodes']],null,'id');
        foreach($source['edges'] ?? [] as $e){self::need(is_array($e) && ($e['frameId'] ?? '')===$frame && isset($nodes[$e['from'] ?? ''],$nodes[$e['to'] ?? '']),'invalid source edge');$out['edges'][]=$e;}
        foreach(['walkableAreas'=>'areas','obstacles'=>'obstacles'] as $key=>$dest)foreach($source[$key] ?? [] as $area){
            self::need(is_array($area) && !array_diff(array_keys($area),['id','type','coordinates','accessible']),'invalid source geometry');
            $type=$key==='walkableAreas'?'polygon':($area['type'] ?? '');self::need(in_array($type,['polygon','line'],true),'invalid obstacle type');
            $points=$area['coordinates'] ?? [];
            if($type==='polygon')$points=self::polygon($points);else{self::need(is_array($points) && array_is_list($points) && count($points)>=2 && count($points)<=100,'invalid obstacle line');$points=array_map(self::point(...),$points);}
            self::need(!isset($area['accessible']) || is_bool($area['accessible']),'accessible must be boolean');
            $out[$dest][]=['id'=>self::text($area['id'] ?? null,80),'frameId'=>$frame,'type'=>$type,'coordinates'=>$points,'accessible'=>$area['accessible'] ?? false,'accuracyMeters'=>(float)$source['accuracyMeters'],'sourceID'=>$id,'sourceVersion'=>$version];
        }
        $merged=self::merge($doc,$out);Camap::validate($merged);return $out;
    }
    private static function merge(array $doc,array $source): array {
        foreach(['nodes','edges'] as $key){$items=array_column($doc[$key],null,'id');foreach($source[$key] as $item){if(isset($items[$item['id']])){self::need($items[$item['id']]==$item,'source object conflicts with map');continue;}$items[$item['id']]=$item;}$doc[$key]=array_values($items);}return $doc;
    }
    public static function analyze(array $document,?array $source=null,array $metadata=[]): array {
        Camap::validate($document);self::need(count($document['edges'])<=5000 && count($document['features'])<=5000,'prepare a smaller campus map');
        $normalized=self::normalizeSource($document,$source);$doc=self::merge($document,$normalized);$map=new Routing($doc);
        $sourceID=$normalized['provenance']['sourceID'] ?? null;
        $oldAreas=array_filter($metadata['areas'] ?? [],fn($a)=>$sourceID===null || ($a['sourceID'] ?? null)!==$sourceID);
        $oldObstacles=array_filter($metadata['obstacles'] ?? [],fn($a)=>$sourceID===null || ($a['sourceID'] ?? null)!==$sourceID);
        $areas=[...array_values($oldAreas),...$normalized['areas']];$obstacles=[...array_values($oldObstacles),...$normalized['obstacles']];
        self::need(count($areas)<=100 && count($obstacles)<=100,'too many combined surveyed geometries');
        $network=[];$bad=[];$unsafe=array_flip($map->unsafeEdges);
        foreach($map->edges as $id=>$e){if($e['closed'] || isset($unsafe[$id]) || self::blocked($e['polyline'],$e['frameId'],$map,$obstacles)){$bad[]=$id;continue;}$network[$id]=$e;}
        $candidates=[];$entrances=[];$diagnostics=[];$limit=30.;$budget=0;$searchBudget=20000;
        foreach($map->features as $door){
            if(!in_array($door['kind'],['door','gate'],true) || !($door['exterior'] ?? false))continue;
            if($door['geometry']['type']!=='point'){$diagnostics[]=['code'=>'entrance_not_point','entranceID'=>$door['id']];continue;}
            $nodes=array_filter($map->nodes,fn($n)=>($n['entranceId'] ?? '')===$door['id']);$nodeIDs=array_column($nodes,'id');
            $connected=false;foreach($network as $e)if(in_array($e['from'],$nodeIDs,true)||in_array($e['to'],$nodeIDs,true)){$connected=true;break;}
            $entry=['entranceID'=>$door['id'],'name'=>$door['name'],'frameId'=>$door['frameId'],'status'=>$connected?'connected':'unconnected','candidateIDs'=>[]];
            if($connected){$entrances[]=$entry;continue;}
            if(++$budget>100){$entry['reasonCode']='preparation_limit';$entrances[]=$entry;continue;}
            $pos=$door['geometry']['coordinates'];$options=[];
            foreach($network as $id=>$e){if($e['frameId']!==$door['frameId'] || in_array($e['from'],$nodeIDs,true)||in_array($e['to'],$nodeIDs,true))continue;
                $line=$e['polyline'];$offset=0.;
                for($i=1;$i<count($line);$i++){
                    $a=$line[$i-1];$b=$line[$i];$dx=$b[0]-$a[0];$dy=$b[1]-$a[1];$len=hypot($dx,$dy);if($len<1e-6)continue;
                    $t=max(0.,min(1.,(($pos[0]-$a[0])*$dx+($pos[1]-$a[1])*$dy)/($len*$len)));$q=[$a[0]+$t*$dx,$a[1]+$t*$dy];$gap=hypot($pos[0]-$q[0],$pos[1]-$q[1]);
                    if($gap<=$limit)$options[]=['edgeID'=>$id,'segment'=>$i,'point'=>$q,'offset'=>$offset+$t*$len,'distance'=>$gap];$offset+=$len;
                }
            }
            usort($options,fn($a,$b)=>$a['distance']<=>$b['distance'] ?: strcmp($a['edgeID'],$b['edgeID']));$seen=[];
            foreach(array_slice($options,0,12) as $target){
                $key=$target['edgeID'];if(isset($seen[$key]))continue;if(count($seen)>=3)break;$seen[$key]=true;
                $line=[$pos,$target['point']];$blocked=self::blocked($line,$door['frameId'],$map,$obstacles);$mode='straight';
                $verified=self::verified($line,$door['frameId'],$areas);
                if($blocked || !$verified){$curve=self::detour($pos,$target['point'],$door['frameId'],$map,$areas,$obstacles,$limit,$searchBudget);if($curve){$line=$curve;$verified=true;$blocked=false;$mode='grid';}}
                if($blocked)continue;
                $precise=true;foreach($areas as $a)if($a['frameId']===$door['frameId'] && $a['accuracyMeters']>3)$precise=false;
                $status=$verified && $precise?'auto_eligible':'needs_confirmation';
                $cid=self::id(self::digest([$doc,$normalized['provenance'],$door['id'],$target,$line]));
                $candidate=['candidateID'=>$cid,'entranceID'=>$door['id'],'frameId'=>$door['frameId'],'targetEdgeID'=>$target['edgeID'],'target'=>$target,'polyline'=>$line,'distanceMeters'=>Routing::length($line),'status'=>$status,'method'=>$mode,'reasonCode'=>$status==='auto_eligible'?'verified_walkable_ground':'walkability_or_alignment_unverified','accessible'=>($door['accessible'] ?? false) && $network[$key]['accessible'] && self::verified($line,$door['frameId'],$areas,true),'covered'=>false];
                $candidates[]=$candidate;$entry['candidateIDs'][]=$cid;
                if(count($entry['candidateIDs'])>=3)break;
            }
            $entry['reasonCode']=$entry['candidateIDs']?'connection_candidates':'no_verified_connection';$entrances[]=$entry;
        }
        // Weak components diagnose islands without incorrectly treating directed edges as two-way routes.
        $adj=[];foreach($map->nodes as $id=>$_)$adj[$id]=[];foreach($network as $e){$adj[$e['from']][]=$e['to'];$adj[$e['to']][]=$e['from'];}
        $seen=[];$components=[];foreach($adj as $id=>$links){if(isset($seen[$id]))continue;$queue=[$id];$ids=[];while($queue){$v=array_pop($queue);if(isset($seen[$v]))continue;$seen[$v]=true;$ids[]=$v;foreach($adj[$v] as $next)if(!isset($seen[$next]))$queue[]=$next;}$components[]=['nodeIDs'=>$ids,'size'=>count($ids)];}
        if(!$network)$diagnostics[]=['code'=>'no_road_network'];if(count($components)>1)$diagnostics[]=['code'=>'disconnected_components','count'=>count($components)];if($bad)$diagnostics[]=['code'=>'excluded_edges','edgeIDs'=>$bad];
        if($searchBudget<=0)$diagnostics[]=['code'=>'grid_search_limit'];
        $invalidSource=array_values(array_intersect(array_values(array_filter($bad,fn($id)=>!$map->edges[$id]['closed'])),array_column($normalized['edges'],'id')));
        return ['ruleVersion'=>self::VERSION,'sourceStatus'=>self::sourceStatus(),'source'=>$normalized,'document'=>$doc,'areas'=>$areas,'obstacles'=>$obstacles,'candidates'=>$candidates,'entrances'=>$entrances,'components'=>$components,'diagnostics'=>$diagnostics,'invalidSourceEdgeIDs'=>$invalidSource];
    }
    private static function slice(array $line,float $from,float $to): array {
        $out=[];$offset=0.;for($i=1;$i<count($line);$i++){$a=$line[$i-1];$b=$line[$i];$len=hypot($b[0]-$a[0],$b[1]-$a[1]);if($len<1e-8)continue;$lo=max($from,$offset);$hi=min($to,$offset+$len);if($hi>=$lo && $hi>=$from && $lo<=$to){foreach([$lo,$hi] as $at){$t=($at-$offset)/$len;$p=[$a[0]+$t*($b[0]-$a[0]),$a[1]+$t*($b[1]-$a[1])];if(!$out || hypot(end($out)[0]-$p[0],end($out)[1]-$p[1])>1e-7)$out[]=$p;}}$offset+=$len;}return $out;
    }
    /** A draft only. Existing publication/rollback controls activation for every student. */
    public static function build(array $report,array $approve=[],array $reject=[],bool $includeAuto=true,array $metadata=[]): array {
        self::need(!$report['invalidSourceEdgeIDs'],'source roads intersect known obstacles; correct the source');
        $byID=array_column($report['candidates'],null,'candidateID');self::need(!array_diff($approve,array_keys($byID)) && !array_diff($reject,array_keys($byID)) && !array_intersect($approve,$reject),'unknown or conflicting candidate decisions');
        $selected=[];$occupied=[];
        foreach($report['candidates'] as $c){if(in_array($c['candidateID'],$reject,true))continue;$manual=in_array($c['candidateID'],$approve,true);if(!$manual && (!$includeAuto || $c['status']!=='auto_eligible'))continue;
            if(isset($occupied[$c['entranceID']])){self::need(!$manual,'only one connection per entrance');continue;}$occupied[$c['entranceID']]=true;$c['confirmation']=$manual?'school_confirmed':'verified_area';$selected[]=$c;
        }
        $doc=$report['document'];$map=new Routing($doc);$nodes=$map->nodes;$edges=$map->edges;$groups=$metadata['edgeGroups'] ?? [];$splits=[];
        foreach($report['diagnostics'] as $diagnostic)if($diagnostic['code']==='excluded_edges')foreach($diagnostic['edgeIDs'] as $eid)if(!$edges[$eid]['closed']){$edges[$eid]['closed']=true;$edges[$eid]['revision']++;}
        foreach($selected as &$c){$edge=$edges[$c['targetEdgeID']];$target=$c['target'];$end=$edge['length'];
            if($target['offset']<0.001)$node=$edge['from'];elseif($end-$target['offset']<0.001)$node=$edge['to'];else{
                $node=self::id($edge['id'].'|split|'.sprintf('%.6f',$target['offset']));$nodes[$node]=['id'=>$node,'revision'=>1,'frameId'=>$edge['frameId'],'position'=>$target['point'],'name'=>'道路接驳点'];$splits[$edge['id']][$node]=['offset'=>$target['offset'],'nodeID'=>$node];
            }$c['targetNodeID']=$node;
        }unset($c);
        foreach($splits as $id=>$points){$e=$edges[$id];$marks=[['offset'=>0.,'nodeID'=>$e['from']],...array_values($points),['offset'=>$e['length'],'nodeID'=>$e['to']]];usort($marks,fn($a,$b)=>$a['offset']<=>$b['offset']);$children=[];
            for($i=1;$i<count($marks);$i++){if($marks[$i]['offset']-$marks[$i-1]['offset']<1e-6)continue;$line=self::slice($e['polyline'],$marks[$i-1]['offset'],$marks[$i]['offset']);$child=$i===1?$id:self::id($id.'|part|'.$marks[$i-1]['nodeID'].'|'.$marks[$i]['nodeID']);$raw=array_diff_key($e,array_flip(['polyline','length']));$raw=array_replace($raw,['id'=>$child,'revision'=>$i===1?$e['revision']+1:1,'from'=>$marks[$i-1]['nodeID'],'to'=>$marks[$i]['nodeID'],'points'=>array_slice($line,1,-1)]);$edges[$child]=$raw;$children[]=$child;}
            $root=$id;foreach($groups as $rid=>$g)if(in_array($id,$g['edgeIDs'],true)){$root=$rid;break;}
            if(isset($groups[$root])){$g=$groups[$root];$new=[];foreach($g['edgeIDs'] as $eid)array_push($new,...($eid===$id?$children:[$eid]));$g['edgeIDs']=$new;$groups[$root]=$g;}
            else $groups[$root]=['edgeIDs'=>$children,'name'=>$e['name'],'frameId'=>$e['frameId'],'polyline'=>$e['polyline']];
        }
        foreach($selected as $c){$door=$map->features[$c['entranceID']];$node=null;foreach($nodes as $n)if(($n['entranceId'] ?? '')===$door['id']){$node=$n['id'];break;}
            if(!$node){$node=self::id($door['id'].'|entrance');$nodes[$node]=['id'=>$node,'revision'=>1,'frameId'=>$door['frameId'],'position'=>$door['geometry']['coordinates'],'name'=>$door['name'],'entranceId'=>$door['id']];}
            if($node!==$c['targetNodeID']){$id=self::id($c['candidateID'].'|connector');$edges[$id]=['id'=>$id,'revision'=>1,'frameId'=>$door['frameId'],'from'=>$node,'to'=>$c['targetNodeID'],'name'=>$door['name'].'接驳','points'=>array_slice($c['polyline'],1,-1),'oneWay'=>false,'accessible'=>$c['confirmation']==='verified_area' && $c['accessible'],'covered'=>false,'closed'=>false];}
        }
        $doc['nodes']=array_values($nodes);$doc['edges']=array_map(fn($e)=>array_diff_key($e,array_flip(['polyline','length'])),array_values($edges));Camap::validate($doc);
        $sources=[];foreach([...($metadata['sources'] ?? []),...($report['source']['provenance']?[$report['source']['provenance']]:[])] as $source)$sources[$source['sourceID']]=$source;
        self::need(count($sources)<=50,'too many combined source providers');
        $resultMeta=['ruleVersion'=>self::VERSION,'frameHashes'=>array_column(array_map(fn($f)=>['id'=>$f['id'],'hash'=>self::digest($f)],$doc['frames']),'hash','id'),'edgeGroups'=>$groups,'areas'=>$report['areas'],'obstacles'=>$report['obstacles'],'sources'=>array_values($sources),'decisions'=>array_map(fn($c)=>array_intersect_key($c,array_flip(['candidateID','entranceID','targetEdgeID','targetNodeID','confirmation','method','distanceMeters'])),$selected),'rejectedCandidateIDs'=>$reject];
        return ['document'=>$doc,'metadata'=>$resultMeta,'selectedConnections'=>count($selected)];
    }
}
