from pathlib import Path
from fractions import Fraction
from statistics import median
import json,sys
base=Path(sys.argv[1]);comparison=json.loads((base/'comparison/comparison.json').read_text());rule=json.loads((base/'pre-registration.json').read_text())
assert comparison['status']=='ready_for_review' and comparison['decision_ready'] and not comparison['errors'] and comparison['complete_pairs']==5
primary=[];guards=[]
for name in rule['primary_wall_workloads']:
 item=comparison['workloads'][name]['wallClock'];pcts=[]
 for pair in item['pairs']:
  a=Fraction(str(pair['control_median']));b=Fraction(str(pair['candidate_median']));assert a>0;pcts.append(100*(b-a)/a)
 center=median(pcts);improving=sum(p<0 for p in pcts)
 primary.append({'workload':name,'median_paired_change_percent':float(center),'improving_pairs':improving,'passed':center<=rule['benefit_rule']['median_paired_percent_at_most'] and improving>=rule['benefit_rule']['improving_pairs_at_least']})
for name,metrics in rule['regression_guards'].items():
 for metric in metrics:
  item=comparison['workloads'][name][metric];over=0;undefined=[]
  for pair in item['pairs']:
   a=Fraction(str(pair['control_median']));b=Fraction(str(pair['candidate_median']));over+=b>a*(1+Fraction(str(rule['regression_rule']['paired_percent_over']))/100)
   if a==0:undefined.append({'pair':pair['pair'],'zero_control':pair['zero_control']})
  guards.append({'workload':name,'metric':metric,'pairs_over_regression_bar':over,'passed':over<rule['regression_rule']['pairs_at_least'],'undefined_percentage_pairs':undefined})
result={'numerical_verdict':'supported' if all(p['passed'] for p in primary) and all(g['passed'] for g in guards) else 'not_supported','valid_complete_pairs':5,'primary_passed':sum(p['passed'] for p in primary),'primary_total':len(primary),'guards_passed':sum(g['passed'] for g in guards),'guards_total':len(guards),'primary':primary,'guards':guards,'adoption_verdict':'requires completed profile/phase/support gates and lead review','notes':['Medians and threshold comparisons recomputed from exact rational representations of exported run medians. Histograms remain quantized.','Zero-baseline regression checks use the equivalent candidate > control * 1.03 relation; no percentage is assigned to a zero baseline.']}
(base/'numerical-verdict.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:v for k,v in result.items() if k not in ['primary','guards','notes']},indent=2))
