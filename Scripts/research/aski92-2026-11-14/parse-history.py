from pathlib import Path
import collections, json, re, sys
source=Path(sys.argv[1]); output=Path(sys.argv[2])
header=re.compile(r'^(ALLOC|FREE|VM_ALLOC|VM_DEALLOC)\s+(0x[0-9a-f]+)(?:-(0x[0-9a-f]+) \[size=(\d+)\])?:\s*$')
live={}; selected=[]; counts=collections.Counter(); unknown=collections.Counter(); errors=[]; ordinal=0; event=None

def consume(e):
    if e is None: return
    kind=e['kind']; address=e['address']; counts[kind]+=1
    if kind not in ('ALLOC','FREE'): return
    if kind=='ALLOC':
        if address in live:
            errors.append({'duplicate_live_address':address,'old':live[address]['event'],'new':e['event']})
        live[address]=e
        if any('TileGridConverter.convert' in line for line in e['stack']):
            e['free_event']=None
            selected.append(e)
    else:
        allocation=live.pop(address,None)
        if allocation is None: counts['unmatched_free']+=1
        elif 'free_event' in allocation:
            allocation['free_event']=e['event'];allocation['free_line']=e['line'];allocation['free_stack']=e['stack']

with source.open() as f:
    for line_no,line in enumerate(f,1):
        m=header.match(line.rstrip('\n'))
        if m:
            consume(event);ordinal+=1
            event={'event':ordinal,'line':line_no,'kind':m[1],'address':m[2],'bytes':int(m[4]) if m[4] else None,'stack':[]}
        elif re.match(r'^\d+\s+\S',line):
            if event: event['stack'].append(line.rstrip())
        elif re.match(r'^[A-Z_]+\s+0x',line): unknown[line.split()[0]]+=1
consume(event)
summary=collections.Counter()
for e in selected:
    frames=[l for l in e['stack'] if 'AskiBenchmarks' in l]
    site=frames[0] if frames else 'none'
    summary[(e['bytes'],site)]+=1
result={'source':str(source),'event_counts':dict(counts),'unknown_event_types':dict(unknown),'errors':errors[:20],'selected_allocations':selected,'unfreed_selected':sum(e['free_event'] is None for e in selected),'source_groups':[{'bytes':b,'frame':s,'count':n} for (b,s),n in summary.most_common()]}
output.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['selected_allocations','source_groups']},indent=2))
for r in result['source_groups'][:35]:print(r)
assert not errors and not unknown, 'allocation event stream is not safely interpretable'
