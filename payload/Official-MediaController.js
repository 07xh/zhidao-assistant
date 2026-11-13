// SPDX-License-Identifier: GPL-3.0-only
// Official video controller for the WebView2 top-level document.
// Controls at most one selected HTMLMediaElement. It never calls platform
// progress APIs, fabricates watch time, spoofs visibility, or submits answers.
(() => {
  'use strict';

  const hostname = String(location.hostname || '').toLowerCase();
  if (!(hostname === 'zhihuishu.com' || hostname.endsWith('.zhihuishu.com'))) return 'not-official';
  // Deliberately do not control iframe documents. Cross-frame players can each
  // contain their own <video>; allowing every frame to autoplay can start many.
  if (window.top !== window.self) {
    try { window.chrome?.webview?.postMessage(JSON.stringify({kind:'player-action',event:'iframe-not-controlled'})); } catch (_) {}
    return 'frame-skipped';
  }

  const desiredRate = __RATE__;
  const autoStart = __AUTO_START__;
  const autoNext = __AUTO_NEXT__;

  function onCoursePlayerPage() {
    const path = String(location.pathname || '');
    if (/(?:exam|homework|question|quiz|assessment|passport|login|testDetail|dohomework)/i.test(path)) return false;
    return /(?:stuStudy|studyVideo|videoStudy|knowledgeStudy|learnPage|courseVideo|\/video(?:\/|$))/i.test(path);
  }

  function report(kind, event, video = null, note = '') {
    try {
      window.chrome?.webview?.postMessage(JSON.stringify({
        kind, event, note: String(note).slice(0, 80),
        rate: video?.playbackRate ?? 0,
        paused: video?.paused ?? true,
        ready: video?.readyState ?? 0
      }));
    } catch (_) {}
  }

  function visible(video) {
    if (!video || !video.isConnected || !video.getClientRects?.().length) return false;
    const style = getComputedStyle(video);
    if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) === 0) return false;
    const rect = video.getBoundingClientRect?.();
    if (rect && (rect.width <= 0 || rect.height <= 0)) return false;
    return true;
  }

  function area(video) {
    const rect = video.getBoundingClientRect?.();
    if (rect && rect.width > 0 && rect.height > 0) return rect.width * rect.height;
    return Math.max(0, Number(video.videoWidth || 0) * Number(video.videoHeight || 0));
  }

  const seen = new WeakSet();
  const states = new WeakMap();
  let primaryVideo = null;
  let visibleVideoCount = 0;
  let lastReportedVideoCount = -1;

  function sourceKey(video) {
    return String(video.currentSrc || video.src || video.getAttribute?.('src') || '');
  }

  function stateFor(video) {
    const key = sourceKey(video);
    let state = states.get(video);
    if (!state || state.source !== key) {
      state = {
        source: key,
        playAttempts: 0,
        playPending: false,
        autoplayBlocked: false,
        nextPending: false,
        nextAdvanced: false,
        nextAttempts: 0
      };
      states.set(video, state);
    }
    return state;
  }

  function choosePrimary(videos) {
    const candidates = videos.filter(visible);
    visibleVideoCount = candidates.length;
    if (!candidates.length) return null;
    // The largest visible video is the conservative main-player candidate.
    // A small playing preview/ad must not outrank a large course player.
    candidates.sort((a, b) => {
      const aArea = area(a), bArea = area(b);
      const aScore = aArea + (a.readyState >= 2 ? 1500 : 0) + (!a.paused ? Math.min(aArea * 0.02, 5000) : 0);
      const bScore = bArea + (b.readyState >= 2 ? 1500 : 0) + (!b.paused ? Math.min(bArea * 0.02, 5000) : 0);
      return bScore - aScore;
    });
    return candidates[0];
  }

  function isPrimary(video) { return !!video && video === primaryVideo; }

  function setRate(video) {
    if (!isPrimary(video)) return false;
    try {
      video.defaultPlaybackRate = desiredRate;
      video.playbackRate = desiredRate;
      const applied = Math.abs(Number(video.playbackRate) - desiredRate) < 0.01;
      if (!applied) report('player-action', 'speed-not-applied', video);
      return applied;
    } catch (_) {
      report('player-action', 'speed-unavailable', video);
      return false;
    }
  }

  function requestPlay(video, fromUser = false) {
    if (!autoStart && !fromUser) return 'autoplay-disabled';
    if (!onCoursePlayerPage() || !isPrimary(video) || !visible(video)) return 'not-primary';
    if (video.ended || !video.paused) return 'already-active';
    if (Number(video.readyState || 0) < 2) return 'not-ready';
    const state = stateFor(video);
    if (state.playPending) return 'play-pending';
    if (state.autoplayBlocked && !fromUser) return 'blocked-until-user-action';
    if (!fromUser && state.playAttempts >= 2) return 'retry-limit';
    if (fromUser) {
      state.autoplayBlocked = false;
      state.playAttempts = 0;
    }
    state.playAttempts += 1;
    state.playPending = true;
    try {
      const result = video.play();
      if (result?.then) {
        result.then(() => {
          state.playPending = false;
          report('player-action', 'autoplay-started', video);
        }).catch(error => {
            state.playPending = false;
            const name = String(error?.name || '');
            if (name === 'NotAllowedError' || name === 'SecurityError') {
              state.autoplayBlocked = true;
              report('player-action', 'autoplay-blocked', video, name);
            } else if (state.playAttempts < 2) {
              report('player-action', 'autoplay-retry-available', video, name || 'play-rejected');
            } else {
              report('player-action', 'autoplay-retry-exhausted', video, name || 'play-rejected');
            }
          });
      } else {
        state.playPending = false;
        report('player-action', 'autoplay-requested', video);
      }
      return 'requested';
    } catch (error) {
      state.playPending = false;
      const name = String(error?.name || '');
      if (name === 'NotAllowedError' || name === 'SecurityError') state.autoplayBlocked = true;
      report('player-action', state.autoplayBlocked ? 'autoplay-blocked' : 'autoplay-retry-available', video, name);
      return 'failed';
    }
  }

  function safeNextControl() {
    // Require a semantic course-content container. If the page does not expose
    // one, fail closed and let the learner choose the next lesson manually.
    const scope = document.querySelector('main, [role="main"], .course-content, .study-content, .classroom-content');
    if (!scope?.querySelectorAll) return null;
    const candidates = scope.querySelectorAll('button, a, [role="button"]');
    const names = /^(?:下一节|下一小节|下一课|下一讲|下一视频|下一个视频|下一章节)$/u;
    const unsafe = /(?:exam|homework|question|quiz|assessment|test|exercise|practice|header|footer|navigation|sidebar)/i;
    const matches = [];
    for (const el of candidates) {
      if (!visible(el) || el.disabled || el.getAttribute('aria-disabled') === 'true') continue;
      if (el.closest('nav, header, footer, aside, form, [role="navigation"], [role="dialog"], [aria-modal="true"]')) continue;
      let node = el;
      let unsafeContext = false;
      while (node && node !== scope.parentElement) {
        const tag = String(node.tagName || '').toLowerCase();
        const role = String(node.getAttribute?.('role') || '').toLowerCase();
        const marker = String(node.className || '') + ' ' + String(node.id || '');
        if (['nav', 'header', 'footer', 'aside', 'form'].includes(tag) || role === 'navigation' || unsafe.test(marker)) {
          unsafeContext = true;
          break;
        }
        if (node === scope) break;
        node = node.parentElement;
      }
      if (unsafeContext) continue;
      if (el.tagName?.toLowerCase() === 'button' && String(el.type || 'button').toLowerCase() !== 'button') continue;
      const label = String(el.getAttribute('aria-label') || el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
      if (!names.test(label)) continue;
      if (el.tagName?.toLowerCase() === 'a') {
        try {
          const url = new URL(el.href, location.href);
          if (url.origin !== location.origin || url.protocol !== 'https:') continue;
        } catch (_) { continue; }
      }
      matches.push(el);
      if (matches.length > 1) return null; // Ambiguous: learner chooses the next lesson.
    }
    return matches.length === 1 ? matches[0] : null;
  }

  function tryNext(video) {
    if (!autoNext || !onCoursePlayerPage() || !isPrimary(video)) return;
    const state = stateFor(video);
    if (state.nextPending || state.nextAdvanced) return;
    state.nextPending = true;
    const endedUrl = location.href;
    const endedSrc = sourceKey(video);
    const attempt = () => {
      if (!isPrimary(video) || !onCoursePlayerPage() || location.href !== endedUrl || !video.ended || sourceKey(video) !== endedSrc) {
        state.nextPending = false;
        return;
      }
      const next = safeNextControl();
      state.nextAttempts += 1;
      if (!next) {
        if (state.nextAttempts < 2) {
          setTimeout(attempt, 1200);
          return;
        }
        state.nextPending = false;
        report('player-action', 'next-not-found', video);
        return;
      }
      state.nextAdvanced = true;
      state.nextPending = false;
      const label = String(next.getAttribute('aria-label') || next.innerText || next.textContent || '').trim();
      report('player-action', 'next-clicked', video, label);
      next.click();
    };
    setTimeout(attempt, 900);
  }

  // Passive, local-only playback heartbeat (not a ZHS platform heartbeat).
  // Observe the real HTML5 media clock; NEVER submit fabricated watch events,
  // seek the video, defeat background pausing, or call a progress endpoint.
  const MONITOR_INTERVAL_MS = 12000;
  const monitor = {
    video: null, source: '', position: null, timestamp: null,
    stallSamples: 0, lastState: '', lastReport: 0, seekPending: false,
    lastVisibility: null
  };

  function resetMonitor(video) {
    monitor.video = video;
    monitor.source = video ? sourceKey(video) : '';
    monitor.position = null;
    monitor.timestamp = null;
    monitor.stallSamples = 0;
    monitor.lastState = '';
    monitor.lastReport = 0;
    monitor.seekPending = false;
    monitor.lastVisibility = null;
  }

  function monotonicNow() {
    // A system wall-clock adjustment must not be mistaken for a playback jump.
    return (typeof performance !== 'undefined' && typeof performance.now === 'function')
      ? performance.now() : Date.now();
  }

  function finiteTime(value) {
    const n = Number(value);
    return Number.isFinite(n) && n >= 0 ? Math.min(n, 864000) : 0;
  }

  function monitorNow(force = false) {
    if (!onCoursePlayerPage()) {
      if (force) report('player-action', 'monitor-not-course-page');
      return 'not-course-page';
    }
    if (!primaryVideo || !visible(primaryVideo)) {
      if (force) report('player-action', 'monitor-no-video');
      return 'no-visible-course-video';
    }
    const video = primaryVideo;
    if (monitor.video !== video || monitor.source !== sourceKey(video)) resetMonitor(video);
    const time = monotonicNow();
    const pageVisible = document.visibilityState !== 'hidden';
    const position = finiteTime(video.currentTime);
    const duration = finiteTime(video.duration);
    const previous = monitor.position;
    const elapsed = monitor.timestamp === null ? 0 : (time - monitor.timestamp) / 1000;
    const rate = Number(video.playbackRate);
    const expectedRate = Number.isFinite(rate) && rate > 0 ? Math.min(rate, 16) : 1;
    const delta = previous === null ? 0 : position - previous;
    let state;
    if (video.ended) state = 'ended';
    else if (video.seeking || monitor.seekPending) state = 'seeking';
    else if (video.paused) state = 'paused';
    else if (Number(video.readyState || 0) < 2) state = 'buffering';
    else if (previous === null || elapsed < 1) state = 'observing';
    else if (elapsed > 45) state = 'sampling-gap';
    else if (monitor.lastVisibility !== null && monitor.lastVisibility !== pageVisible) state = 'visibility-changed';
    else if (delta < -0.5 || delta > Math.max(3, elapsed * expectedRate * 1.5 + 2)) state = 'position-jump';
    else if (delta >= 0.5) state = 'advancing';
    else state = 'no-advance';

    if (state === 'no-advance') {
      monitor.stallSamples += 1;
      state = monitor.stallSamples >= 2 ? 'stalled' : 'observing';
    } else {
      monitor.stallSamples = 0;
    }
    // Never equate local movement to server-accepted study time.
    const shouldReport = force || state !== monitor.lastState ||
      (state === 'advancing' && time - monitor.lastReport >= 60000);
    monitor.position = position;
    monitor.timestamp = time;
    monitor.lastVisibility = pageVisible;
    if (state !== 'seeking') monitor.seekPending = false;
    if (shouldReport) {
      monitor.lastState = state;
      monitor.lastReport = time;
      try {
        window.chrome?.webview?.postMessage(JSON.stringify({
          kind: 'playback-health', event: state,
          positionSeconds: Math.round(position), durationSeconds: Math.round(duration),
          rate: Number(video.playbackRate) || 0,
          paused: !!video.paused,
          pageVisible
        }));
      } catch (_) {}
    }
    return state;
  }

  function register(video) {
    if (!(video instanceof HTMLVideoElement) || seen.has(video)) return;
    seen.add(video);
    video.addEventListener('seeking', () => {
      if (isPrimary(video)) monitor.seekPending = true;
    });
    video.addEventListener('seeked', () => {
      if (isPrimary(video)) resetMonitor(video); // user seek is not watched time
    });
    video.addEventListener('loadedmetadata', () => {
      scan();
      const state = stateFor(video); // resets attempts when SPA reuses the element for another source
      if (isPrimary(video)) {
        setRate(video);
        if (state.playAttempts === 0) requestPlay(video);
      }
    });
    video.addEventListener('canplay', () => {
      scan();
      if (isPrimary(video)) requestPlay(video);
    });
    video.addEventListener('play', () => {
      if (isPrimary(video)) {
        setRate(video);
        report('media-status', 'play', video);
      } else {
        report('player-action', 'secondary-video-playing', video, 'controller-did-not-start-this-video');
      }
    });
    video.addEventListener('pause', () => { if (isPrimary(video)) report('media-status', 'pause', video); });
    video.addEventListener('ratechange', () => { if (isPrimary(video)) report('media-status', 'ratechange', video); });
    video.addEventListener('waiting', () => { if (isPrimary(video)) report('media-status', 'waiting', video); });
    video.addEventListener('ended', () => {
      if (isPrimary(video)) {
        report('media-status', 'ended', video);
        tryNext(video);
      }
    });
    video.addEventListener('error', () => { if (isPrimary(video)) report('player-action', 'media-error', video); });
  }

  function scan() {
    const videos = Array.from(document.querySelectorAll('video'));
    videos.forEach(register);
    const chosen = choosePrimary(videos);
    if (visibleVideoCount !== lastReportedVideoCount) {
      lastReportedVideoCount = visibleVideoCount;
      if (visibleVideoCount > 1) report('player-action', 'multiple-videos-visible', chosen, String(visibleVideoCount));
    }
    if (chosen !== primaryVideo) {
      primaryVideo = chosen;
      resetMonitor(primaryVideo);
      if (primaryVideo) {
        const state = stateFor(primaryVideo);
        report('player-action', 'primary-selected', primaryVideo, 'visible-videos=' + visibleVideoCount);
        setRate(primaryVideo);
        if (state.playAttempts === 0) requestPlay(primaryVideo);
      } else {
        report('player-action', 'no-primary-video');
      }
    }
    return primaryVideo ? 'primary-selected' : 'no-video';
  }

  function applyRate() {
    scan();
    if (!primaryVideo) return 'no-primary-video';
    return setRate(primaryVideo) ? 'rate-applied' : 'rate-not-applied';
  }

  function playPrimaryFromUserGesture() {
    scan();
    if (!primaryVideo) return 'no-primary-video';
    return requestPlay(primaryVideo, true);
  }

  if (window.__zhidaoOfficialController) {
    window.__zhidaoOfficialController.scan();
    return 'already-installed';
  }
  window.__zhidaoOfficialController = {
    scan, applyRate, playPrimaryFromUserGesture, monitorNow,
    getPrimaryVideo: () => primaryVideo,
    getVisibleVideoCount: () => visibleVideoCount,
    rate: desiredRate, autoStart, autoNext
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', scan, {once: true});
  } else {
    scan();
  }
  new MutationObserver(scan).observe(document.documentElement || document, {childList: true, subtree: true});
  // Observe the player's *actual* timeline at a low frequency.  No network calls.
  setInterval(() => { scan(); monitorNow(); }, MONITOR_INTERVAL_MS);
  return 'installed';
})()
