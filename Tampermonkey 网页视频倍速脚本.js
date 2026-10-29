// ==UserScript==
// @name         Tampermonkey 网页视频倍速脚本
// @namespace    https://local.sai/
// @version      1.1.1
// @description  在 Bilibili、抖音、YouTube 和小红书页面左侧提供轻量视频倍速控制。
// @author       Sai
// @match        *://*.bilibili.com/*
// @match        *://*.douyin.com/*
// @match        *://*.youtube.com/*
// @match        *://youtu.be/*
// @match        *://*.xiaohongshu.com/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
  'use strict';

  if (window.top !== window.self || document.getElementById('sai-video-speed-controller')) {
    return;
  }

  const MIN_RATE = 0.1;
  const MAX_RATE = 3.0;
  const STEP = 0.1;
  const HOST_ID = 'sai-video-speed-controller';
  const observedVideos = new WeakSet();

  let currentRate = 1.0;
  let hasUserSelectedRate = false;
  let activeVideo = null;
  let refreshTimer = 0;
  let restoreTimer = 0;

  const host = document.createElement('div');
  host.id = HOST_ID;
  host.setAttribute('data-sai-video-speed-controller', '');
  host.style.display = 'none';

  const shadow = host.attachShadow({ mode: 'open' });
  const style = document.createElement('style');
  style.textContent = `
    :host {
      all: initial;
      position: fixed;
      left: 0;
      top: 50%;
      z-index: 2147483647;
      transform: translateY(-50%);
      color-scheme: dark;
      pointer-events: auto;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    }

    * {
      box-sizing: border-box;
    }

    .controller {
      display: flex;
      width: 30px;
      flex-direction: column;
      align-items: flex-start;
      filter: drop-shadow(0 2px 6px rgb(0 0 0 / 28%));
    }

    button {
      margin: 0;
      border: 0;
      padding: 0;
      color: #fff;
      background: rgb(18 18 22 / 88%);
      font: 600 12px/1 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      cursor: pointer;
      -webkit-tap-highlight-color: transparent;
    }

    button:hover,
    button:focus-visible {
      background: rgb(0 161 214 / 96%);
      outline: none;
    }

    button:active {
      transform: translateY(1px);
    }

    .handle {
      width: 26px;
      height: 24px;
      border-radius: 0 8px 8px 0;
      font-size: 10px;
      letter-spacing: -0.4px;
    }

    /* 展开菜单：调整为 8 行按钮（6个预设 + 2个加减微调） */
    .menu {
      display: grid;
      width: 26px;
      grid-template-rows: repeat(8, 26px);
      gap: 2px;
      margin-top: 3px;
      opacity: 0;
      visibility: hidden;
      transform: translateY(-4px);
      transition: opacity 120ms ease, transform 120ms ease, visibility 120ms;
    }

    .controller[data-open="true"] .menu {
      opacity: 1;
      visibility: visible;
      transform: translateY(0);
    }

    .menu button {
      width: 26px;
      height: 26px;
      border-radius: 0 7px 7px 0;
    }

    /* 预设倍速按钮字体 */
    .menu .preset {
      font-size: 9px;
      font-weight: 500;
    }

    /* 加减按钮字体 */
    .menu .increase,
    .menu .decrease {
      font-size: 15px;
    }

    @media (prefers-reduced-motion: reduce) {
      .menu {
        transition: none;
      }
    }
  `;

  function createButton(className, text, ariaLabel, title) {
    const button = document.createElement('button');
    button.className = className;
    button.type = 'button';
    button.textContent = text;
    button.title = title;
    button.setAttribute('aria-label', ariaLabel);
    return button;
  }

  const controller = document.createElement('div');
  controller.className = 'controller';
  controller.dataset.open = 'false';

  const handleButton = createButton('handle', '1.0', '展开视频倍速控制', '视频倍速：1.0×');
  handleButton.setAttribute('aria-expanded', 'false');

  const menu = document.createElement('div');
  menu.className = 'menu';
  menu.setAttribute('aria-hidden', 'true');

  // 创建预设倍速按钮 (0.5, 1.0, 1.5, 2.0, 2.5, 3.0)
  const presetRates = [0.5, 1.0, 1.5, 2.0, 2.5, 3.0];
  presetRates.forEach((rate) => {
    const btn = createButton('preset', `${rate}×`, `设置倍速为 ${rate} 倍`, `切换至 ${rate}×`);
    btn.addEventListener('click', () => setDesiredRate(rate));
    menu.appendChild(btn);
  });

  // 创建微调按钮 (+0.1, -0.1)
  const increaseButton = createButton('increase', '+', '视频加速 0.1 倍', '加速 0.1 倍');
  const decreaseButton = createButton('decrease', '−', '视频减速 0.1 倍', '减速 0.1 倍');

  increaseButton.addEventListener('click', () => adjustRate(STEP));
  decreaseButton.addEventListener('click', () => adjustRate(-STEP));

  menu.appendChild(increaseButton);
  menu.appendChild(decreaseButton);

  controller.appendChild(handleButton);
  controller.appendChild(menu);
  shadow.appendChild(style);
  shadow.appendChild(controller);

  function clampAndRoundRate(value) {
    const rounded = Math.round(Number(value) * 10) / 10;
    return Math.min(MAX_RATE, Math.max(MIN_RATE, rounded));
  }

  function isElementVisible(video) {
    if (!video.isConnected) {
      return false;
    }

    const style = getComputedStyle(video);
    if (style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity) === 0) {
      return false;
    }

    const rect = video.getBoundingClientRect();
    return rect.width > 1 && rect.height > 1;
  }

  function getVisibleArea(video) {
    if (!isElementVisible(video)) {
      return 0;
    }

    const rect = video.getBoundingClientRect();
    const visibleWidth = Math.max(0, Math.min(rect.right, innerWidth) - Math.max(rect.left, 0));
    const visibleHeight = Math.max(0, Math.min(rect.bottom, innerHeight) - Math.max(rect.top, 0));
    return visibleWidth * visibleHeight;
  }

  function scoreVideo(video) {
    if (!isElementVisible(video)) {
      return Number.NEGATIVE_INFINITY;
    }

    const rect = video.getBoundingClientRect();
    const visibleArea = getVisibleArea(video);
    const elementArea = Math.max(1, rect.width * rect.height);
    const visibleRatio = visibleArea / elementArea;
    const centerX = rect.left + rect.width / 2;
    const centerY = rect.top + rect.height / 2;
    const centerDistance = Math.hypot(centerX - innerWidth / 2, centerY - innerHeight / 2);

    let score = visibleArea + visibleRatio * 500000 - centerDistance;
    if (!video.paused && !video.ended) {
      score += 2000000;
    }
    if (document.pictureInPictureElement === video) {
      score += 4000000;
    }
    if (document.fullscreenElement === video || document.fullscreenElement?.contains(video)) {
      score += 5000000;
    }
    if (video.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA) {
      score += 10000;
    }

    return score;
  }

  function getVideos() {
    return Array.from(document.querySelectorAll('video'));
  }

  function getActiveVideo(videos = getVideos()) {
    let bestVideo = null;
    let bestScore = Number.NEGATIVE_INFINITY;

    for (const video of videos) {
      const score = scoreVideo(video);
      if (score > bestScore) {
        bestVideo = video;
        bestScore = score;
      }
    }

    return bestVideo;
  }

  function updateRateDisplay() {
    const text = currentRate.toFixed(1);
    handleButton.textContent = text;
    handleButton.title = `视频倍速：${text}×`;
    handleButton.setAttribute('aria-label', `视频倍速 ${text} 倍，点击展开控制`);
  }

  function setVideoRate(video, rate) {
    if (!video || !video.isConnected) {
      return;
    }

    if (Math.abs(video.playbackRate - rate) > 0.001) {
      video.playbackRate = rate;
    }
  }

  function applyCurrentRate(video = getActiveVideo()) {
    activeVideo = video;
    if (hasUserSelectedRate && video) {
      setVideoRate(video, currentRate);
    }
  }

  function syncRateFromVideo(video) {
    if (hasUserSelectedRate || !video || !Number.isFinite(video.playbackRate)) {
      return;
    }

    currentRate = clampAndRoundRate(video.playbackRate);
    updateRateDisplay();
  }

  function setDesiredRate(rate) {
    currentRate = clampAndRoundRate(rate);
    hasUserSelectedRate = true;
    updateRateDisplay();
    applyCurrentRate();
  }

  function adjustRate(delta) {
    const video = getActiveVideo();
    const baseRate = hasUserSelectedRate
      ? currentRate
      : clampAndRoundRate(video?.playbackRate ?? currentRate);
    setDesiredRate(baseRate + delta);
  }

  function setMenuOpen(open) {
    controller.dataset.open = String(open);
    handleButton.setAttribute('aria-expanded', String(open));
    menu.setAttribute('aria-hidden', String(!open));
  }

  function getMountPoint() {
    const fullscreenElement = document.fullscreenElement;
    if (fullscreenElement && !(fullscreenElement instanceof HTMLMediaElement)) {
      return fullscreenElement;
    }
    return document.documentElement;
  }

  function mountHost() {
    const mountPoint = getMountPoint();
    if (host.parentNode !== mountPoint) {
      mountPoint.appendChild(host);
    }
  }

  function scheduleRestore(video) {
    if (!hasUserSelectedRate || video !== getActiveVideo()) {
      return;
    }

    clearTimeout(restoreTimer);
    restoreTimer = window.setTimeout(() => {
      if (hasUserSelectedRate && video === getActiveVideo()) {
        setVideoRate(video, currentRate);
      }
    }, 0);
  }

  function observeVideo(video) {
    if (observedVideos.has(video)) {
      return;
    }

    observedVideos.add(video);
    video.addEventListener('ratechange', () => scheduleRestore(video));
    video.addEventListener('play', () => {
      activeVideo = video;
      if (hasUserSelectedRate) {
        setVideoRate(video, currentRate);
      } else {
        syncRateFromVideo(video);
      }
      scheduleRefresh(0);
    });
    video.addEventListener('loadedmetadata', () => {
      if (video === getActiveVideo()) {
        applyCurrentRate(video);
      }
      scheduleRefresh(0);
    });
  }

  function refresh() {
    const videos = getVideos();
    videos.forEach(observeVideo);

    const nextActiveVideo = getActiveVideo(videos);
    const hasRelevantVideo = videos.some(isElementVisible);
    host.style.display = hasRelevantVideo ? '' : 'none';

    if (!hasRelevantVideo) {
      setMenuOpen(false);
      activeVideo = null;
      return;
    }

    if (nextActiveVideo !== activeVideo) {
      activeVideo = nextActiveVideo;
      if (hasUserSelectedRate) {
        applyCurrentRate(nextActiveVideo);
      } else {
        syncRateFromVideo(nextActiveVideo);
      }
    }
  }

  function scheduleRefresh(delay = 120) {
    clearTimeout(refreshTimer);
    refreshTimer = window.setTimeout(refresh, delay);
  }

  handleButton.addEventListener('click', () => {
    setMenuOpen(controller.dataset.open !== 'true');
  });

  document.addEventListener('pointerdown', (event) => {
    if (controller.dataset.open === 'true' && !host.contains(event.target)) {
      setMenuOpen(false);
    }
  }, true);

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      setMenuOpen(false);
    }
  });

  document.addEventListener('fullscreenchange', () => {
    mountHost();
    scheduleRefresh(0);
  });

  const observer = new MutationObserver(() => scheduleRefresh());
  observer.observe(document.documentElement, { childList: true, subtree: true });

  mountHost();
  updateRateDisplay();
  refresh();
  window.setInterval(refresh, 1500);
})();