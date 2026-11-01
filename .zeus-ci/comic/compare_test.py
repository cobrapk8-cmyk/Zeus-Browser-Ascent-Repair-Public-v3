import importlib.util,pathlib,unittest
spec=importlib.util.spec_from_file_location('compare',pathlib.Path(__file__).with_name('compare.py'));module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class ParityGateTests(unittest.TestCase):
    def test_empty_or_simulator_results_cannot_prove_parity(self):
        result=module.compare({},{});self.assertFalse(result['equivalent']);self.assertIn('physical_devices_required',result['problems'])
    def test_character_error_counts_real_substitutions_and_unicode(self):
        self.assertEqual(module.cer('こんにちは','こんにちは'),(0,5));self.assertEqual(module.cer('ABC','ADC'),(1,3));self.assertEqual(module.cer('é','e\u0301'),(0,1))
    def test_gate_accepts_complete_evidence_and_rejects_blank_ground_truth(self):
        import copy
        baseline={'dataset_sha256':'a'*64,'physical_device':True,'comparison_pair':'old-phones','mode':'fastest','samples':[]}
        for language in ['ko','ja','zh']:
            for i in range(100):baseline['samples'].append({'id':language+str(i),'language':language,'expected':'hello','recognized':'hello','missed_lines':0,'seam_errors':0,'displayed':True,'first_balloon_ms':100,'completed_ms':150})
        self.assertTrue(module.compare(baseline,copy.deepcopy(baseline))['equivalent'])
        blank=copy.deepcopy(baseline)
        for row in blank['samples']:row['expected']=''
        self.assertFalse(module.compare(blank,copy.deepcopy(blank))['equivalent'])
        negative=copy.deepcopy(baseline);negative['samples'][0]['completed_ms']=-1
        self.assertFalse(module.compare(baseline,negative)['equivalent'])
if __name__=='__main__':unittest.main()
