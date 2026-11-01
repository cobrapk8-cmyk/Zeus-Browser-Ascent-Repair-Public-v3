"""Compare exported physical-device results; missing evidence fails closed.

Both JSON inputs contain dataset_sha256, physical_device, comparison_pair,
mode and samples. Each sample contains id, language, expected, recognized,
missed_lines, seam_errors, displayed, first_balloon_ms and completed_ms.
No expected field or unmeasured metric is silently invented.
"""
import argparse, json, sys, unicodedata, math, re

def cer(expected,actual):
    expected=''.join(unicodedata.normalize('NFC',expected).split())
    actual=''.join(unicodedata.normalize('NFC',actual).split())
    row=list(range(len(actual)+1))
    for i,a in enumerate(expected,1):
        following=[i]
        for j,b in enumerate(actual,1):following.append(min(following[-1]+1,row[j]+1,row[j-1]+(a!=b)))
        row=following
    return row[-1],len(expected)

def percentile(values,p):
    values=sorted(values)
    return values[min(len(values)-1,max(0,int((len(values)-1)*p)))] if values else None

def compare(baseline,candidate):
    problems=[]
    for key in ['dataset_sha256','comparison_pair','mode']:
        if not baseline.get(key) or baseline.get(key)!=candidate.get(key):problems.append('mismatched_or_missing_'+key)
    if not re.fullmatch(r'[a-fA-F0-9]{64}',str(baseline.get('dataset_sha256',''))):problems.append('invalid_dataset_sha256')
    if baseline.get('physical_device') is not True or candidate.get('physical_device') is not True:problems.append('physical_devices_required')
    required={'id','language','expected','recognized','missed_lines','seam_errors','displayed','first_balloon_ms','completed_ms'}
    def rows(d):
        result={}
        for row in d.get('samples',[]):
            if not isinstance(row,dict) or not required<=row.keys():problems.append('incomplete_sample');continue
            strings=['id','language','expected','recognized']
            metrics=['missed_lines','seam_errors','first_balloon_ms','completed_ms']
            if (not all(isinstance(row[k],str) for k in strings) or not row['id'] or not row['expected'].strip()
                or type(row['displayed']) is not bool or any(type(row[k]) not in [int,float] or not math.isfinite(row[k]) or row[k]<0 for k in metrics)
                or row['completed_ms']<row['first_balloon_ms']):
                problems.append('invalid_sample');continue
            if row['id'] in result:problems.append('duplicate_sample')
            result[row['id']]=row
        return result
    old,new=rows(baseline),rows(candidate)
    if old.keys()!=new.keys():problems.append('sample_set_mismatch')
    if len(old)<300:problems.append('fewer_than_300_samples')
    summary={}
    for language in ['ko','ja','zh']:
        ids=[key for key in old.keys()&new.keys() if old[key]['language']==language]
        if len(ids)<100:problems.append('insufficient_samples_'+language)
        aggregates=[]
        for values in [old,new]:
            edits=characters=missed=seams=0;first=[];completed=[];shown=0
            for key in ids:
                row=values[key]
                if row['expected']!=old[key]['expected'] or row['language']!=language:problems.append('ground_truth_mismatch')
                e,n=cer(row['expected'],row['recognized']);edits+=e;characters+=n
                missed+=row['missed_lines'];seams+=row['seam_errors'];shown+=row['displayed'] is True
                first.append(row['first_balloon_ms']);completed.append(row['completed_ms'])
            aggregates.append({'cer':edits/max(1,characters),'missed_lines':missed,'seam_errors':seams,'displayed':shown,'first_p50_ms':percentile(first,.5),'first_p95_ms':percentile(first,.95),'complete_p95_ms':percentile(completed,.95)})
        summary[language]={'baseline':aggregates[0],'zeus':aggregates[1],'count':len(ids)}
        for metric in ['cer','missed_lines','seam_errors','first_p50_ms','first_p95_ms','complete_p95_ms']:
            if aggregates[0][metric] is None or aggregates[1][metric] is None:problems.append('missing_metric_'+metric)
            elif aggregates[1][metric]>aggregates[0][metric]:problems.append('regression_'+language+'_'+metric)
        if aggregates[1]['displayed']!=len(ids):problems.append('display_failed_'+language)
    return {'equivalent':not problems,'problems':sorted(set(problems)),'languages':summary}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('ascent');parser.add_argument('zeus');args=parser.parse_args()
    result=compare(json.load(open(args.ascent)),json.load(open(args.zeus)))
    print(json.dumps(result,ensure_ascii=False,indent=2));sys.exit(0 if result['equivalent'] else 1)
