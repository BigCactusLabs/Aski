"""Read complete malloc_history events; use ordered intervals, never clock durations."""
from pathlib import Path
import json,sys,collections
parsed=Path(sys.argv[1]);out=Path(sys.argv[2]);arm=sys.argv[3]
d=json.loads(parsed.read_text());assert not d['errors'] and not d['unknown_event_types']
intervals=[]
for e in d['selected_allocations']:
 stack='\n'.join(e['stack'])
 # Runtime metadata can have the same source caller, but is not array storage.
 if 'swift_allocObject' not in stack:continue
 if not any(t in stack for t in ('_ContiguousArrayBuffer','_ArrayBuffer','_createNewBuffer')):continue
 if 'TilePalette.makeColorSamples' in stack:kind='samples'
 elif 'KMeansRefinement.makeSamples' in stack:kind='samples'
 elif 'WuQuantizer.init' in stack:kind='wu-tables'
 elif 'KMeansRefinement.refine' in stack:kind='kmeans-working'
 elif 'WuQuantizer.palette' in stack:kind='wu-split'
 else:continue
 assert e['free_event'] is not None,('unfreed selected buffer',e['event'],kind)
 assert e['free_event']>e['event']
 intervals.append({**e,'category':kind})
counts=collections.Counter(e['category'] for e in intervals)
assert counts['samples']==7,counts
assert counts['wu-tables']==49,counts
assert counts['kmeans-working']>0,counts
steps=[]
for e in intervals:
 steps.append((e['event'],e['bytes'],e['category'],e['event']))
 steps.append((e['free_event'],-e['bytes'],e['category'],e['event']))
live=collections.Counter();peak=0;peak_event=None;peak_by_category=None
for index,delta,kind,generation in sorted(steps):
 live[kind]+=delta
 assert live[kind]>=0
 total=sum(live.values())
 if total>peak:peak=total;peak_event=index;peak_by_category=dict(live)
assert not sum(live.values())
samples=[e for e in intervals if e['category']=='samples'];overlaps=[]
for sample in samples:
 others=[e for e in intervals if e['category']!='samples' and max(sample['event'],e['event'])<min(sample['free_event'],e['free_event'])]
 overlaps.append({'sample_generation':sample['event'],'sample_bytes':sample['bytes'],'sample_free_event':sample['free_event'],'overlap_counts':dict(collections.Counter(e['category'] for e in others)),'overlap_generations':[e['event'] for e in others]})
# Pair each conversion's seven table allocations with its sample allocation.
tables=[e for e in intervals if e['category']=='wu-tables']
anchors=[min(samples[i]['event'],tables[i*7]['event']) for i in range(7)]
conversions=[]
for i,start in enumerate(anchors):
 stop=anchors[i+1] if i<6 else float('inf')
 group=[e for e in intervals if start<=e['event']<stop]
 assert all(e['free_event']<stop for e in group), 'algorithm storage crosses conversion boundary'
 events=sorted([(e['event'],e['bytes']) for e in group]+[(e['free_event'],-e['bytes']) for e in group])
 current=0;maximum=0
 for _,delta in events:
  current+=delta;assert current>=0;maximum=max(maximum,current)
 assert current==0
 conversions.append({'conversion':i,'role':'warmup' if i==0 else 'iteration','start_event':start,'last_free_event':max(e['free_event'] for e in group),'peak_live_requested_bytes':maximum,'sample_bytes':samples[i]['bytes'],'wu_table_count':sum(e['category']=='wu-tables' for e in group)})
result={'arm':arm,'event_counts':d['event_counts'],'counts':dict(counts),'conversions':conversions,'peak_live_requested_bytes':peak,'peak_event':peak_event,'peak_by_category':peak_by_category,'sample_overlaps':overlaps,'intervals':intervals,'limits':['Ordered events only; no clock timestamps or durations.','Bytes are recorded native malloc requests, including instrument and Swift array headers; not mapped capacity or process RSS.','Includes sample arrays, Wu tables/split arrays, and K-means working arrays identified by source stack and Swift array allocation frames. Excludes common input lattice, output grid, runtime metadata, framework caches and VM.','Seven conversions include one warmup plus six benchmark iterations; this is a diagnostic outside timed pairs.']}
out.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['intervals','sample_overlaps']},indent=2))
