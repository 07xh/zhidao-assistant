'use strict';
const fs = require('fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(__dirname + '/payload/Official-MediaController.js', 'utf8');

function harness({
  url = 'https://ai-smart-course-student-pro.zhihuishu.com/singleCourse/knowledgeStudy/100/200',
  start = true, next = true, buttons = [], videos = [], hasMain = true, iframe = false
} = {}) {
  const parsed = new URL(url);
  const messages = [];
  const pendingTimers = [];
  const intervals = [];
  let nowMs = 0;
  const main = { parentElement: null, querySelectorAll: () => buttons };
  const location = { hostname: parsed.hostname, pathname: parsed.pathname, href: parsed.href };
  const root = {};
  class Video {
    constructor({ width = 640, height = 360, src = 'https://cdn.example/video1.mp4', playImpl = null } = {}) {
      this.events = {};
      this.readyState = 4;
      this.playbackRate = 1;
      this.defaultPlaybackRate = 1;
      this.paused = true;
      this.ended = false;
      this.currentTime = 0;
      this.duration = 120;
      this.seeking = false;
      this.isConnected = true;
      this.currentSrc = src;
      this.src = src;
      this.videoWidth = width;
      this.videoHeight = height;
      this.rect = { width, height, x: 0, y: 0 };
      this.playCount = 0;
      this.playImpl = playImpl;
      this.parentElement = null;
    }
    getClientRects() { return [1]; }
    getBoundingClientRect() { return this.rect; }
    getAttribute(name) { return name === 'src' ? this.src : null; }
    addEventListener(name, fn) { (this.events[name] ||= []).push(fn); }
    fire(name) { for (const fn of (this.events[name] || [])) fn(); }
    play() {
      this.playCount++;
      if (this.playImpl) return this.playImpl(this);
      this.paused = false;
      return Promise.resolve();
    }
  }
  const ctx = {
    location,
    HTMLVideoElement: Video,
    window: { top: null, self: null, chrome: { webview: { postMessage: s => messages.push(JSON.parse(s)) } } },
    document: {
      readyState: 'complete', documentElement: root,
      querySelectorAll: selector => selector === 'video' ? videos : [],
      querySelector: () => hasMain ? main : null,
      addEventListener() {}
    },
    MutationObserver: class { observe() {} },
    getComputedStyle: () => ({ display: 'block', visibility: 'visible', opacity: '1' }),
    performance: { now: () => nowMs },
    setTimeout: fn => pendingTimers.push(fn),
    setInterval: fn => intervals.push(fn),
    Date: class Clock extends Date { static now() { return nowMs; } },
    URL, console
  };
  ctx.window.top = iframe ? {} : ctx.window;
  ctx.window.self = ctx.window;
  const script = source.replaceAll('__RATE__', '1.5')
    .replaceAll('__AUTO_START__', String(start))
    .replaceAll('__AUTO_NEXT__', String(next));
  const result = vm.runInNewContext(script, ctx);
  return {
    ctx, Video, messages, pendingTimers, intervals, location, buttons, videos, result, main,
    tick(ms = 12000) { nowMs += ms; for (const fn of intervals) fn(); },
    advance(ms = 12000) { nowMs += ms; }
  };
}
function makeButton(label, { tag = 'BUTTON', type = 'button', parent = null, href = '' } = {}) {
  return {
    tagName: tag, type, href, innerText: label, textContent: label,
    isConnected: true, disabled: false, parentElement: parent,
    getClientRects: () => [1], getBoundingClientRect: () => ({ width: 100, height: 30 }),
    getAttribute: name => name === 'aria-label' ? null : name === 'role' ? null : null,
    closest: selector => {
      if (selector.includes('nav') && parent?.tagName === 'NAV') return parent;
      if (selector.includes('form') && parent?.tagName === 'FORM') return parent;
      if (selector.includes('dialog') && parent?.tagName === 'DIALOG') return parent;
      return null;
    },
    clickCount: 0, click() { this.clickCount++; }
  };
}
async function flush() { await Promise.resolve(); await Promise.resolve(); }
async function run() {
  const passed = [];
  {
    const h = harness({ url: 'https://ai.zhihuishu.com/' });
    const v = new h.Video(); h.videos.push(v); h.ctx.window.__zhidaoOfficialController.scan();
    assert.equal(v.playCount, 0); passed.push('portal-not-autoplay');
  }
  {
    const h = harness(); const v = new h.Video(); h.videos.push(v);
    h.ctx.window.__zhidaoOfficialController.scan(); await flush();
    assert.equal(v.playCount, 1); assert.equal(v.playbackRate, 1.5);
    passed.push('course-autoplay-and-rate');
  }
  {
    const h = harness({ start: false }); const v = new h.Video(); h.videos.push(v);
    h.ctx.window.__zhidaoOfficialController.scan();
    assert.equal(v.playCount, 0); passed.push('autoplay-disabled');
  }
  {
    const h = harness(); const small = new h.Video({ width: 240, height: 135 });
    const large = new h.Video({ width: 1280, height: 720 }); h.videos.push(small, large);
    h.ctx.window.__zhidaoOfficialController.scan(); await flush();
    assert.equal(large.playCount, 1); assert.equal(small.playCount, 0);
    assert.equal(large.playbackRate, 1.5); assert.equal(small.playbackRate, 1);
    assert(h.messages.some(x => x.event === 'multiple-videos-visible'));
    passed.push('only-largest-primary-video-is-started');
  }
  {
    const h = harness({ iframe: true }); const v = new h.Video(); h.videos.push(v);
    assert.equal(h.result, 'frame-skipped'); assert.equal(v.playCount, 0);
    passed.push('iframe-not-controlled');
  }
  {
    let calls = 0;
    const h = harness();
    const v = new h.Video({ playImpl: () => { calls++; return calls === 1 ? Promise.reject(Object.assign(new Error('transient'), { name: 'AbortError' })) : Promise.resolve().then(() => { v.paused = false; }); } });
    h.videos.push(v); h.ctx.window.__zhidaoOfficialController.scan(); await flush();
    v.fire('canplay'); await flush();
    assert.equal(v.playCount, 2); passed.push('transient-play-error-retries-once');
  }
  {
    let calls = 0;
    const h = harness();
    const v = new h.Video({ playImpl: () => { calls++; return Promise.reject(Object.assign(new Error('blocked'), { name: 'NotAllowedError' })); } });
    h.videos.push(v); h.ctx.window.__zhidaoOfficialController.scan(); await flush();
    v.fire('canplay'); await flush();
    assert.equal(v.playCount, 1);
    assert.equal(h.ctx.window.__zhidaoOfficialController.playPrimaryFromUserGesture(), 'requested');
    assert.equal(v.playCount, 2); passed.push('autoplay-policy-block-does-not-loop-and-manual-retry-available');
  }
  {
    const h = harness(); const small = new h.Video({ width: 200, height: 112 });
    const large = new h.Video({ width: 800, height: 450 }); h.videos.push(small, large);
    h.ctx.window.__zhidaoOfficialController.scan();
    assert.equal(h.ctx.window.__zhidaoOfficialController.applyRate(), 'rate-applied');
    assert.equal(large.playbackRate, 1.5); assert.equal(small.playbackRate, 1);
    passed.push('apply-rate-targets-primary-only');
  }
  {
    const button = makeButton('下一节');
    const h = harness({ buttons: [button] }); const v = new h.Video(); h.videos.push(v);
    h.ctx.window.__zhidaoOfficialController.scan(); v.paused = true; v.ended = true; v.fire('ended');
    assert.equal(h.pendingTimers.length, 1); h.pendingTimers.shift()();
    assert.equal(button.clickCount, 1); passed.push('next-control-clicked-only-inside-main');
  }
  {
    const first = makeButton('下一节');
    const second = makeButton('下一小节');
    const h = harness({ buttons: [first, second] });
    const v = new h.Video(); h.videos.push(v);
    h.ctx.window.__zhidaoOfficialController.scan(); v.ended = true; v.fire('ended');
    h.pendingTimers.shift()(); h.pendingTimers.shift()();
    assert.equal(first.clickCount, 0); assert.equal(second.clickCount, 0);
    passed.push('ambiguous-next-control-does-not-auto-click');
  }
  {
    const button = makeButton('下一节');
    const h = harness({ buttons: [button], hasMain: false }); const v = new h.Video(); h.videos.push(v);
    h.ctx.window.__zhidaoOfficialController.scan(); v.ended = true; v.fire('ended');
    h.pendingTimers.shift()(); h.pendingTimers.shift()();
    assert.equal(button.clickCount, 0); passed.push('no-semantic-main-container-fails-closed');
  }
  {
    const nav = { tagName: 'NAV', parentElement: null };
    const button = makeButton('下一节', { parent: nav });
    const h = harness({ buttons: [button] }); const v = new h.Video(); h.videos.push(v);
    h.ctx.window.__zhidaoOfficialController.scan(); v.ended = true; v.fire('ended');
    h.pendingTimers.shift()(); h.pendingTimers.shift()();
    assert.equal(button.clickCount, 0); passed.push('navigation-next-button-rejected');
  }
  {
    const button = makeButton('下一题');
    const h = harness({ buttons: [button] }); const v = new h.Video(); h.videos.push(v);
    h.ctx.window.__zhidaoOfficialController.scan(); v.ended = true; v.fire('ended');
    h.pendingTimers.shift()(); h.pendingTimers.shift()();
    assert.equal(button.clickCount, 0); passed.push('question-button-rejected');
  }
  {
    const button = makeButton('下一节');
    const h = harness({ buttons: [button] }); const v = new h.Video(); h.videos.push(v);
    h.ctx.window.__zhidaoOfficialController.scan(); v.ended = true; v.fire('ended');
    h.location.href += '?lesson=next'; h.pendingTimers.shift()();
    assert.equal(button.clickCount, 0); passed.push('route-change-prevents-double-advance');
  }
  {
    const h = harness(); const v = new h.Video(); h.videos.push(v);
    h.ctx.window.__zhidaoOfficialController.scan(); await flush();
    const oldCount = v.playCount;
    v.currentSrc = 'https://cdn.example/video2.mp4'; v.src = v.currentSrc; v.paused = true;
    v.fire('loadedmetadata'); await flush();
    assert.equal(v.playCount, oldCount + 1); passed.push('spa-source-change-resets-play-state');
  }
  {
    const h = harness(); let resolvePlay;
    const v = new h.Video({ playImpl: () => new Promise(resolve => { resolvePlay = () => { v.paused = false; resolve(); }; }) });
    h.videos.push(v); h.ctx.window.__zhidaoOfficialController.scan();
    v.fire('canplay'); v.fire('canplay');
    assert.equal(v.playCount, 1); resolvePlay(); await flush();
    passed.push('duplicate-canplay-does-not-create-parallel-play-calls');
  }
  {
    const h = harness(); const small = new h.Video({ width: 200, height: 112 });
    const large = new h.Video({ width: 800, height: 450 }); h.videos.push(small, large);
    h.ctx.window.__zhidaoOfficialController.scan();
    small.paused = false; small.fire('play');
    assert(h.messages.some(x => x.event === 'secondary-video-playing'));
    passed.push('secondary-video-is-observed-but-not-controlled');
  }
  {
    const h = harness(); const main = new h.Video({ width: 900, height: 506 }); h.videos.push(main);
    h.ctx.window.__zhidaoOfficialController.scan();
    const preview = new h.Video({ width: 180, height: 101 }); h.videos.push(preview);
    h.ctx.window.__zhidaoOfficialController.scan();
    assert.equal(main.playCount, 1); assert.equal(preview.playCount, 0);
    assert(h.messages.some(x => x.event === 'multiple-videos-visible'));
    passed.push('late-secondary-video-is-detected-without-being-started');
  }
  {
    const h = harness(); const v = new h.Video(); h.videos.push(v);
    h.ctx.window.__zhidaoOfficialController.scan(); await flush();
    const controller = h.ctx.window.__zhidaoOfficialController;
    assert.equal(controller.monitorNow(true), 'observing');
    v.currentTime = 12; h.tick();
    assert.equal(controller.monitorNow(true), 'observing'); // same instant should not claim time advance
    h.advance(12000); v.currentTime = 24;
    assert.equal(controller.monitorNow(true), 'advancing');
    assert(h.messages.some(m => m.kind === 'playback-health' && m.event === 'advancing' && m.positionSeconds === 24));
    passed.push('passive-clock-observation-detects-real-advance');
  }
  {
    const h = harness(); const v = new h.Video(); h.videos.push(v);
    const c = h.ctx.window.__zhidaoOfficialController; c.scan(); await flush();
    c.monitorNow(true); h.advance(12000); assert.equal(c.monitorNow(true), 'observing');
    h.advance(12000); assert.equal(c.monitorNow(true), 'stalled');
    assert(h.messages.some(m => m.kind === 'playback-health' && m.event === 'stalled'));
    v.paused = true; h.advance(12000); assert.equal(c.monitorNow(true), 'paused');
    passed.push('stalled-and-paused-are-distinct');
  }
  {
    const h = harness(); const v = new h.Video(); h.videos.push(v);
    const c = h.ctx.window.__zhidaoOfficialController; c.scan(); await flush();
    c.monitorNow(true);
    v.seeking = true; v.fire('seeking'); h.advance(12000); v.currentTime = 100;
    assert.equal(c.monitorNow(true), 'seeking');
    v.seeking = false; v.fire('seeked');
    assert.equal(c.monitorNow(true), 'observing');
    passed.push('user-seek-reset-never-counted-as-watching');
  }
  {
    const h = harness({ url: 'https://ai.zhihuishu.com/' });
    const v = new h.Video(); h.videos.push(v);
    const c = h.ctx.window.__zhidaoOfficialController; c.scan();
    assert.equal(c.monitorNow(true), 'not-course-page');
    assert.equal(h.messages.filter(m => m.kind === 'playback-health').length, 0);
    passed.push('portal-page-has-no-false-playing-heartbeat');
  }
  {
    const h = harness(); const v = new h.Video(); h.videos.push(v);
    const c = h.ctx.window.__zhidaoOfficialController; c.scan(); await flush();
    v.paused = false; c.monitorNow(true);
    h.advance(12000); v.currentTime = 12;
    assert.equal(c.monitorNow(true), 'advancing');
    h.advance(12000); v.currentTime = 80;
    assert.equal(c.monitorNow(true), 'position-jump');
    passed.push('large-unmarked-media-jump-not-counted-as-normal-advance');
  }
  {
    const h = harness(); const v = new h.Video(); h.videos.push(v);
    const c = h.ctx.window.__zhidaoOfficialController; c.scan(); await flush();
    v.paused = false; c.monitorNow(true);
    h.advance(60000); v.currentTime = 60;
    assert.equal(c.monitorNow(true), 'sampling-gap');
    h.advance(12000); v.currentTime = 72;
    assert.equal(c.monitorNow(true), 'advancing');
    passed.push('long-timer-throttling-rebaselines-without-overclaiming');
  }
  {
    const h = harness(); const v = new h.Video(); h.videos.push(v);
    const c = h.ctx.window.__zhidaoOfficialController; c.scan(); await flush();
    v.paused = false; c.monitorNow(true);
    h.advance(12000); v.currentTime = 12;
    assert.equal(c.monitorNow(true), 'advancing');
    h.ctx.document.visibilityState = 'hidden';
    h.advance(12000); v.currentTime = 24;
    assert.equal(c.monitorNow(true), 'visibility-changed');
    h.advance(12000); v.currentTime = 36;
    assert.equal(c.monitorNow(true), 'advancing');
    passed.push('visibility-transition-is-diagnostic-not-progress-credit');
  }
  console.log(`Passed ${passed.length} controller tests:\n${passed.map((x, i) => `${i + 1}. ${x}`).join('\n')}`);
}
run().catch(error => { console.error(error); process.exitCode = 1; });
