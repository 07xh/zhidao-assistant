"""Local-only heartbeat observability lab for playback diagnostics.

This experiment does not know any learning-platform API URL, cookie, request
format, study-credit formula, or completion endpoint. Its simulated acknowledgments
are *laboratory* acknowledgments, not proof of remote learning progress.
Standard-library only; no network operations.
"""
from __future__ import annotations

from dataclasses import dataclass, asdict
from collections import deque
from typing import Optional
import argparse
import json
import math


@dataclass(frozen=True)
class Sample:
    clock_s: float
    media_s: float
    paused: bool = False
    ready_state: int = 4
    rate: float = 1.0
    seeking: bool = False
    ended: bool = False
    visible: bool = True
    source: str = "synthetic-video"


@dataclass(frozen=True)
class LocalEvent:
    seq: int
    reason: str
    source: str
    position_s: float
    sample_clock_s: float
    delta_s: Optional[float]
    visible: bool
    note: str = "local observation only; no learning credit"


class PlaybackObserver:
    """Pure local state machine. Never invents position or watch duration."""

    def __init__(self, *, max_sampling_gap_s: float = 45.0, stall_threshold: int = 2):
        self.max_sampling_gap_s = max_sampling_gap_s
        self.stall_threshold = stall_threshold
        self.previous: Optional[Sample] = None
        self.stall_samples = 0
        self.seq = 0

    def observe(self, sample: Sample) -> LocalEvent:
        self.seq += 1
        prev = self.previous
        delta: Optional[float] = None
        if (not all(math.isfinite(v) for v in (sample.clock_s, sample.media_s, sample.rate))
                or sample.media_s < 0 or sample.rate <= 0):
            reason = 'invalid-sample'
        elif prev is None or prev.source != sample.source:
            reason = 'source-changed' if prev is not None else 'baseline'
        else:
            elapsed = sample.clock_s - prev.clock_s
            delta = sample.media_s - prev.media_s
            if elapsed < 0:
                reason = 'clock-regression'
            elif sample.ended:
                reason = 'ended'
            elif sample.seeking:
                reason = 'seeking'
            elif sample.paused:
                reason = 'paused'
            elif sample.ready_state < 3:
                reason = 'buffering'
            elif elapsed < 1:
                reason = 'insufficient-interval'
            elif elapsed > self.max_sampling_gap_s:
                reason = 'sampling-gap'
            elif prev.visible != sample.visible:
                reason = 'visibility-changed'
            elif delta < -0.5 or delta > max(3.0, elapsed * min(sample.rate, 16.0) * 1.5 + 2.0):
                reason = 'position-jump'
            elif delta >= 0.5:
                reason = 'advancing'
            else:
                reason = 'no-advance'

        if reason == 'no-advance':
            self.stall_samples += 1
            if self.stall_samples >= self.stall_threshold:
                reason = 'stalled'
        else:
            self.stall_samples = 0
        # An invalid sample must not poison the next valid baseline.
        if reason != 'invalid-sample':
            self.previous = sample
        return LocalEvent(self.seq, reason, sample.source,
                          sample.media_s, sample.clock_s, delta, sample.visible)


@dataclass(frozen=True)
class LabAck:
    event_seq: int
    status: str  # accepted / duplicate / transient-error
    attempts: int
    environment: str = 'offline-lab-only'


class MemoryLabReceiver:
    """Fake receiver in the same process, with deterministic fault injection."""

    def __init__(self, fail_on_calls: Optional[set[int]] = None):
        self.fail_on_calls = set(fail_on_calls or ())
        self.calls = 0
        self.accepted: set[int] = set()

    def receive(self, event: LocalEvent) -> str:
        self.calls += 1
        if self.calls in self.fail_on_calls:
            return 'transient-error'
        if event.seq in self.accepted:
            return 'duplicate'
        self.accepted.add(event.seq)
        return 'accepted'


class BoundedLabQueue:
    """Deterministic, bounded retries to an in-memory receiver only."""

    def __init__(self, *, max_events: int = 100, max_attempts: int = 3):
        self.max_events = max_events
        self.max_attempts = max_attempts
        self.pending: deque[LocalEvent] = deque()
        self.dropped = 0

    def enqueue(self, event: LocalEvent) -> bool:
        if len(self.pending) >= self.max_events:
            self.dropped += 1
            return False
        self.pending.append(event)
        return True

    def drain(self, receiver: MemoryLabReceiver) -> list[LabAck]:
        acks = []
        while self.pending:
            event = self.pending.popleft()
            for attempt in range(1, self.max_attempts + 1):
                result = receiver.receive(event)
                if result in {'accepted', 'duplicate'} or attempt == self.max_attempts:
                    acks.append(LabAck(event.seq, result, attempt))
                    break
        return acks


def make_scenario(name: str) -> list[Sample]:
    base = [Sample(0, 0), Sample(12, 12), Sample(24, 24)]
    if name == 'normal':
        return base + [Sample(36, 36)]
    if name == 'stall':
        return base + [Sample(36, 24), Sample(48, 24), Sample(60, 24, paused=True)]
    if name == 'seek':
        return base + [Sample(36, 100, seeking=True), Sample(48, 112)]
    if name == 'unmarked-jump':
        return base + [Sample(36, 101)]
    if name == 'background-gap':
        return base + [Sample(124, 90, visible=False), Sample(136, 102, visible=False)]
    if name == 'clock-regression':
        return base + [Sample(23, 36), Sample(35, 48)]
    if name == 'source-switch':
        return base + [Sample(36, 0, source='synthetic-video-next'), Sample(48, 12, source='synthetic-video-next')]
    raise ValueError(f'Unknown scenario: {name}')


def run_scenario(name: str, fail_on_calls: Optional[set[int]] = None) -> dict:
    observer = PlaybackObserver()
    receiver = MemoryLabReceiver(fail_on_calls)
    queue = BoundedLabQueue()
    events = [observer.observe(sample) for sample in make_scenario(name)]
    for event in events:
        queue.enqueue(event)
    acks = queue.drain(receiver)
    return {
        'environment': 'offline-lab-only',
        'scenario': name,
        'events': [asdict(e) for e in events],
        'lab_acknowledgments': [asdict(a) for a in acks],
        'server_study_credit': 'not-tested-and-not-inferred',
        'dropped_events': queue.dropped,
    }


def main():
    parser = argparse.ArgumentParser(description='Offline playback heartbeat research: never connects to Zhidao')
    parser.add_argument('--scenario', default='normal', choices=['normal', 'stall', 'seek', 'unmarked-jump',
                       'background-gap', 'clock-regression', 'source-switch'])
    parser.add_argument('--demo-retry', action='store_true', help='Inject a fake one-time receiver error')
    args = parser.parse_args()
    print(json.dumps(run_scenario(args.scenario, {2} if args.demo_retry else None),
                     ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
