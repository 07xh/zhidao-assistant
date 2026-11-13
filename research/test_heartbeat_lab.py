"""Self-contained offline tests (no platform credentials and no network)."""
import unittest
import math
from heartbeat_lab import Sample, PlaybackObserver, MemoryLabReceiver, BoundedLabQueue, run_scenario


class OfflineResearchTests(unittest.TestCase):
    def test_normal(self):
        r = run_scenario('normal')
        self.assertEqual([e['reason'] for e in r['events']], ['baseline', 'advancing', 'advancing', 'advancing'])
        self.assertEqual(r['server_study_credit'], 'not-tested-and-not-inferred')

    def test_stall_then_pause(self):
        reasons = [x['reason'] for x in run_scenario('stall')['events']]
        self.assertEqual(reasons[-3:], ['no-advance', 'stalled', 'paused'])

    def test_explicit_seek(self):
        self.assertIn('seeking', [x['reason'] for x in run_scenario('seek')['events']])

    def test_unmarked_seek(self):
        self.assertIn('position-jump', [x['reason'] for x in run_scenario('unmarked-jump')['events']])

    def test_background_gap(self):
        self.assertIn('sampling-gap', [x['reason'] for x in run_scenario('background-gap')['events']])

    def test_clock_regression(self):
        self.assertIn('clock-regression', [x['reason'] for x in run_scenario('clock-regression')['events']])

    def test_source_switch(self):
        self.assertIn('source-changed', [x['reason'] for x in run_scenario('source-switch')['events']])

    def test_invalid_samples_not_poison_baseline(self):
        o = PlaybackObserver()
        o.observe(Sample(0, 0))
        self.assertEqual(o.observe(Sample(2, math.nan)).reason, 'invalid-sample')
        self.assertEqual(o.observe(Sample(12, 12)).reason, 'advancing')

    def test_in_memory_retry(self):
        result = run_scenario('normal', {2})
        self.assertEqual(result['lab_acknowledgments'][1]['attempts'], 2)
        self.assertEqual(result['lab_acknowledgments'][1]['status'], 'accepted')

    def test_deduplication(self):
        o = PlaybackObserver()
        event = o.observe(Sample(0, 0))
        receiver = MemoryLabReceiver()
        self.assertEqual(receiver.receive(event), 'accepted')
        self.assertEqual(receiver.receive(event), 'duplicate')

    def test_queue_overflow(self):
        o = PlaybackObserver()
        q = BoundedLabQueue(max_events=1)
        self.assertTrue(q.enqueue(o.observe(Sample(0, 0))))
        self.assertFalse(q.enqueue(o.observe(Sample(12, 12))))
        self.assertEqual(q.dropped, 1)

    def test_exhausted_retry_keeps_failure_visible(self):
        o = PlaybackObserver()
        event = o.observe(Sample(0, 0))
        q = BoundedLabQueue(max_attempts=3)
        q.enqueue(event)
        acks = q.drain(MemoryLabReceiver({1,2,3}))
        self.assertEqual(acks[0].status, 'transient-error')
        self.assertEqual(acks[0].attempts, 3)

    def test_no_network_imports(self):
        from pathlib import Path
        code = (Path(__file__).parent/'heartbeat_lab.py').read_text()
        for token in ('requests', 'urllib', 'http.client', 'socket', 'cookies.json', 'zhihuishu.com'):
            self.assertNotIn(token, code)


if __name__ == '__main__':
    unittest.main(verbosity=2)
