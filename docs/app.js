import {
  COMPONENT_GROUPS, SEGMENTS, TOGGLE_GROUPS,
  buildConfigure, componentStatus, defaultConfig, effectiveComponents, normalizeConfig,
  requiresGpl, sanitizeCustom, setToggle,
} from './configure.js';

const form = document.querySelector('#build-form');
const segmentsNode = document.querySelector('#segments');
const toggleGroupsNode = document.querySelector('#toggle-groups');
const componentModeNode = document.querySelector('#component-mode');
const componentModeHintNode = document.querySelector('#component-mode-hint');
const componentGroupsNode = document.querySelector('#component-groups');
const customOptionsInput = document.querySelector('#custom-options');
const toggleNoticeNode = document.querySelector('#toggle-notice');
const configurePreviewNode = document.querySelector('#configure-preview');
const configNotesNode = document.querySelector('#config-notes');
const copyConfigButton = document.querySelector('#copy-config');
const resetConfigButton = document.querySelector('#reset-config');
const refreshButton = document.querySelector('#refresh-builds');
const detectedRepoNode = document.querySelector('#detected-repo');
const issuesStatusNode = document.querySelector('#issues-status');
const formMessageNode = document.querySelector('#form-message');
const buildListNode = document.querySelector('#build-list');
const targetPlatformSelect = document.querySelector('#target-platform');
const targetArchSelect = document.querySelector('#target-arch');

const BUILD_TITLE_PREFIX = '[build]';
const ISSUE_TEMPLATE = 'build.yml';
// Unauthenticated GitHub API calls are limited to 60/hour per IP; each refresh costs two.
const AUTO_REFRESH_MS = 10 * 60 * 1000;
const SAFE_REF_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._/-]*$/;
const REPOSITORY_PATTERN = /^(https?:\/\/github\.com\/|git@github\.com:)[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+?(\.git)?\/?$/;
const CONFIG_STORAGE_KEY = 'ffmpeg-builder-config-v2';

const state = {
  owner: '',
  repo: '',
  refreshHandle: null,
  config: defaultConfig(),
};

// ── Repository detection ────────────────────────────────────────────────────

function detectRepository() {
  const { hostname, pathname } = window.location;
  const pathParts = pathname.split('/').filter(Boolean);

  if (hostname.endsWith('.github.io')) {
    return {
      owner: hostname.split('.')[0] || '',
      repo: pathParts[0] || '',
    };
  }

  if (pathParts.length >= 2) {
    return { owner: pathParts[0], repo: pathParts[1] };
  }

  return { owner: '', repo: '' };
}

function repoUrl(path = '') {
  return `https://github.com/${state.owner}/${state.repo}${path}`;
}

// ── GitHub API helper (unauthenticated, public data only) ──────────────────

async function githubFetch(path) {
  const response = await fetch(`https://api.github.com${path}`, {
    headers: { Accept: 'application/vnd.github+json' },
  });

  if (!response.ok) {
    if (response.status === 403 || response.status === 429) {
      throw new Error('GitHub API 访问次数已达上限（未登录时每小时 60 次），请稍后再刷新。');
    }
    if (response.status === 404) {
      throw new Error('无法读取仓库信息：仓库不存在或为私有仓库。私有仓库请直接在 GitHub 上查看 Issues 与 Actions。');
    }
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.message || `GitHub API 请求失败: ${response.status}`);
  }

  return response.json();
}

function setMessage(node, type, message) {
  node.className = `${node.dataset.baseClass} ${type}`.trim();
  node.textContent = message;
}

function makeLink(href, text) {
  const a = document.createElement('a');
  a.href = href;
  a.target = '_blank';
  a.rel = 'noreferrer';
  a.textContent = text;
  return a;
}

async function loadRepositoryInfo() {
  if (!state.owner || !state.repo) {
    detectedRepoNode.textContent = '无法自动识别，请以 https://<owner>.github.io/<repo>/ 形式访问';
    issuesStatusNode.textContent = '未知';
    return;
  }

  detectedRepoNode.replaceChildren(makeLink(repoUrl(), `${state.owner}/${state.repo}`));

  try {
    const repo = await githubFetch(`/repos/${state.owner}/${state.repo}`);
    if (repo.has_issues) {
      issuesStatusNode.textContent = '已开启';
    } else {
      issuesStatusNode.replaceChildren(
        '未开启，无法提交编译。请到 ',
        makeLink(repoUrl('/settings'), 'Settings → General → Features'),
        ' 勾选 Issues。',
      );
    }
  } catch (error) {
    issuesStatusNode.textContent = error.message;
  }
}

// ── Form helpers ────────────────────────────────────────────────────────────

const ARCH_OPTIONS = {
  linux:   [['x86_64', 'x86_64'], ['x86', 'x86 (32-bit)'], ['arm64', 'arm64 (AArch64)'], ['armv7', 'armv7 (ARM 32-bit)']],
  macos:   [['x86_64', 'x86_64 (Intel)'], ['arm64', 'arm64 (Apple Silicon)'], ['universal', 'Universal (fat binary)']],
  windows: [['x86_64', 'x86_64'], ['x86', 'x86 (32-bit，实验性)'], ['arm64', 'arm64 (AArch64)']],
  all:     [['x86_64', 'x86_64'], ['arm64', 'arm64'], ['universal', 'Universal (macOS fat + x86_64 others)']],
};

function updateArchOptions() {
  const options = ARCH_OPTIONS[targetPlatformSelect.value] || ARCH_OPTIONS.linux;
  const current = targetArchSelect.value;
  targetArchSelect.innerHTML = '';
  options.forEach(([value, label]) => {
    const opt = document.createElement('option');
    opt.value = value;
    opt.textContent = label;
    if (value === current) opt.selected = true;
    targetArchSelect.appendChild(opt);
  });
}

// ── configure option builder ────────────────────────────────────────────────

// The controls are rendered once from the model in configure.js; every change updates
// state.config and syncConfigUI() reflects it back into the DOM. Invalid choices are made
// unavailable in the controls themselves instead of being validated afterwards.

function configContext() {
  return { platform: targetPlatformSelect.value };
}

function loadSavedConfig() {
  try {
    return normalizeConfig(JSON.parse(localStorage.getItem(CONFIG_STORAGE_KEY) || 'null'));
  } catch {
    return defaultConfig();
  }
}

function saveConfig() {
  try {
    localStorage.setItem(CONFIG_STORAGE_KEY, JSON.stringify(state.config));
  } catch {
    // Storage may be unavailable (private mode); the page works without it.
  }
}

function makeSegmented(container, options, onSelect) {
  container.replaceChildren(...options.map((option) => {
    const button = document.createElement('button');
    button.type = 'button';
    button.setAttribute('role', 'radio');
    button.dataset.value = option.id;
    button.textContent = option.label;
    if (option.flags) button.title = option.flags.join(' ') || '（不添加参数）';
    button.addEventListener('click', () => onSelect(option.id));
    return button;
  }));
}

function syncSegmented(container, value) {
  container.querySelectorAll('button').forEach((button) => {
    button.setAttribute('aria-checked', String(button.dataset.value === value));
  });
}

function makeChip(text, onChange) {
  const label = document.createElement('label');
  label.className = 'choice';
  const input = document.createElement('input');
  input.type = 'checkbox';
  input.addEventListener('change', () => onChange(input.checked));
  const span = document.createElement('span');
  span.textContent = text;
  label.append(input, span);
  return label;
}

// Briefly highlight controls changed indirectly (dependencies, custom flags).
function flashControls(keys) {
  keys.forEach((key) => {
    const [kind, id] = key.split(':');
    const node = {
      segment: () => segmentsNode.querySelector(`[data-segment="${id}"]`),
      toggle: () => toggleGroupsNode.querySelector(`[data-toggle="${id}"]`),
      group: () => componentGroupsNode.querySelector(`[data-group="${id}"]`),
      components: () => componentModeNode,
    }[kind]?.();
    if (!node) return;
    node.classList.remove('flash');
    void node.offsetWidth; // restart the animation
    node.classList.add('flash');
  });
}

function setToggleFromUI(item, checked) {
  const result = setToggle(state.config, item.id, checked);
  updateConfig(result.config);
  const others = result.changed.filter((id) => id !== item.id);
  const labels = others.map((id) => TOGGLE_GROUPS.flatMap((group) => group.items).find((entry) => entry.id === id).label);
  toggleNoticeNode.textContent = others.length
    ? (checked
      ? `已同时开启 ${labels.join('、')}（${item.label} 依赖它）。`
      : `已同时关闭 ${labels.join('、')}（依赖 ${item.label}）。`)
    : '';
  flashControls(others.map((id) => `toggle:${id}`));
}

function renderConfigControls() {
  segmentsNode.replaceChildren(...SEGMENTS.map((segment) => {
    const group = document.createElement('div');
    group.className = 'choice-group';
    const title = document.createElement('span');
    title.className = 'group-title';
    title.textContent = segment.label;
    const control = document.createElement('div');
    control.className = 'segmented';
    control.setAttribute('role', 'radiogroup');
    control.setAttribute('aria-label', segment.label);
    control.dataset.segment = segment.id;
    makeSegmented(control, segment.options, (value) => updateConfig({ [segment.id]: value }));
    const hint = document.createElement('small');
    hint.className = 'muted';
    hint.dataset.hintFor = segment.id;
    group.append(title, control, hint);
    return group;
  }));

  toggleGroupsNode.replaceChildren(...TOGGLE_GROUPS.map((group) => {
    const wrapper = document.createElement('div');
    wrapper.className = 'choice-group';
    const title = document.createElement('span');
    title.className = 'group-title';
    title.textContent = group.label;
    const chips = document.createElement('div');
    chips.className = 'choices chips';
    group.items.forEach((item) => {
      const chip = makeChip(item.label, (checked) => setToggleFromUI(item, checked));
      chip.dataset.toggle = item.id;
      chip.title = `${item.hint}\n${[...(item.on || []), ...(item.off || [])].join(' / ')}`;
      chips.appendChild(chip);
    });
    wrapper.append(title, chips);
    return wrapper;
  }));

  makeSegmented(componentModeNode, [
    { id: 'all', label: '全部组件' },
    { id: 'slim', label: '精简' },
  ], (value) => updateConfig({ componentMode: value }));

  componentGroupsNode.replaceChildren(...COMPONENT_GROUPS.map((group) => {
    const details = document.createElement('details');
    details.className = 'component-group';
    details.dataset.group = group.id;
    const summary = document.createElement('summary');
    const name = document.createElement('span');
    name.textContent = group.label;
    const count = document.createElement('span');
    count.className = 'muted count';
    summary.append(name, count);

    const setSelection = (names) => {
      updateConfig({ components: { ...state.config.components, [group.id]: names } });
    };
    const tools = document.createElement('div');
    tools.className = 'component-tools';
    [['全选', () => setSelection([...group.items])], ['清空', () => setSelection([])], ['常用', () => setSelection([...group.defaults])]]
      .forEach(([text, action]) => {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'secondary small';
        button.textContent = text;
        button.addEventListener('click', action);
        tools.appendChild(button);
      });

    const chips = document.createElement('div');
    chips.className = 'choices chips';
    group.items.forEach((item) => {
      const chip = makeChip(item, (checked) => {
        const current = state.config.components[group.id] || [];
        // Keep the catalogue order so the generated flag is stable.
        setSelection(group.items.filter((entry) => (entry === item ? checked : current.includes(entry))));
      });
      chip.dataset.component = item;
      if (requiresGpl(group.id, item)) {
        const badge = document.createElement('span');
        badge.className = 'badge';
        badge.textContent = 'GPL';
        chip.appendChild(badge);
      }
      chips.appendChild(chip);
    });

    details.append(summary, tools, chips);
    return details;
  }));
}

function syncConfigUI() {
  const { config } = state;
  const context = configContext();

  SEGMENTS.forEach((segment) => {
    syncSegmented(segmentsNode.querySelector(`[data-segment="${segment.id}"]`), config[segment.id]);
    const option = segment.options.find((item) => item.id === config[segment.id]);
    segmentsNode.querySelector(`[data-hint-for="${segment.id}"]`).textContent = option?.hint || '';
  });

  toggleGroupsNode.querySelectorAll('[data-toggle]').forEach((chip) => {
    chip.querySelector('input').checked = Boolean(config.toggles[chip.dataset.toggle]);
  });

  syncSegmented(componentModeNode, config.componentMode);
  const slim = config.componentMode === 'slim';
  componentModeHintNode.textContent = slim
    ? '先禁用全部组件（--disable-everything），只编译下面勾选的项目，体积最小。灰色项目当前不可用，悬停查看原因。'
    : '编译 FFmpeg 自带的全部编解码器、封装格式、协议与滤镜。';
  componentGroupsNode.hidden = !slim;
  COMPONENT_GROUPS.forEach((group) => {
    const node = componentGroupsNode.querySelector(`[data-group="${group.id}"]`);
    const selected = effectiveComponents(config, context, group.id);
    node.querySelector('.count').textContent = `${selected.length} / ${group.items.length}`;
    node.querySelectorAll('[data-component]').forEach((chip) => {
      const name = chip.dataset.component;
      const status = componentStatus(config, context, group.id, name);
      const input = chip.querySelector('input');
      input.checked = selected.includes(name);
      input.disabled = !status.available || Boolean(status.locked);
      chip.classList.toggle('unavailable', !status.available);
      chip.classList.toggle('locked', Boolean(status.locked));
      chip.title = status.reason || `--enable-${group.id}=${name}`;
    });
  });

  if (customOptionsInput.value !== config.custom) {
    customOptionsInput.value = config.custom;
  }

  const { options, notes } = buildConfigure(config, context);
  configurePreviewNode.textContent = options;
  configNotesNode.replaceChildren(...notes.map((note) => {
    const li = document.createElement('li');
    li.className = 'muted';
    li.textContent = note;
    return li;
  }));
}

function updateConfig(patch) {
  state.config = { ...state.config, ...patch };
  saveConfig();
  syncConfigUI();
}

async function copyConfigure() {
  try {
    await navigator.clipboard.writeText(configurePreviewNode.textContent);
    copyConfigButton.textContent = '已复制';
  } catch {
    copyConfigButton.textContent = '复制失败';
  }
  window.setTimeout(() => { copyConfigButton.textContent = '复制'; }, 1500);
}

function readForm() {
  const formData = new FormData(form);
  const value = (name) => String(formData.get(name) || '').trim();
  return {
    sourceRepository: value('sourceRepository'),
    sourceRef: value('sourceRef'),
    targetPlatform: value('targetPlatform'),
    targetArch: value('targetArch'),
    packageFormat: value('packageFormat'),
    configureOptions: buildConfigure(state.config, configContext()).options,
  };
}

// Mirrors scripts/resolve-params.sh so mistakes are caught before leaving the page.
function validate(params) {
  if (!REPOSITORY_PATTERN.test(params.sourceRepository)) {
    return '源码仓库只支持 GitHub 地址，例如 https://github.com/FFmpeg/FFmpeg';
  }
  if (params.sourceRef && !SAFE_REF_PATTERN.test(params.sourceRef)) {
    return '源码分支 / tag / commit 含有不允许的字符。';
  }
  return '';
}

function buildIssueUrl(params) {
  const title = `${BUILD_TITLE_PREFIX} ${params.targetPlatform}/${params.targetArch} ${params.sourceRef || 'HEAD'}`;
  const query = new URLSearchParams({
    template: ISSUE_TEMPLATE,
    title,
    source_repository: params.sourceRepository,
    source_ref: params.sourceRef,
    target_platform: params.targetPlatform,
    target_arch: params.targetArch,
    package_format: params.packageFormat,
    configure_options: params.configureOptions,
  });
  return repoUrl(`/issues/new?${query}`);
}

function handleSubmit(event) {
  event.preventDefault();

  if (!state.owner || !state.repo) {
    setMessage(formMessageNode, 'status-error', '无法识别当前仓库，请检查 Pages 访问地址。');
    return;
  }

  const params = readForm();
  const error = validate(params);
  if (error) {
    setMessage(formMessageNode, 'status-error', error);
    return;
  }

  const url = buildIssueUrl(params);
  window.open(url, '_blank', 'noopener');

  formMessageNode.className = `${formMessageNode.dataset.baseClass} status-warn`;
  formMessageNode.replaceChildren(
    '已在新标签页打开预填好的 Issue，请在 GitHub 上点击 “Submit new issue” 提交。没有自动打开？',
    makeLink(url, '点此打开'),
    '。提交后可在下方“编译记录”中查看进度。',
  );
}

// ── Build records ───────────────────────────────────────────────────────────

function runStatusLabel(run) {
  if (!run) return '等待工作流启动（或提交人无权限，未执行）';
  if (run.status !== 'completed') return run.status === 'queued' ? '排队中' : '编译中';
  if (run.conclusion === 'success') return '已完成';
  if (run.conclusion === 'skipped') return '未执行（标题或权限不符）';
  return `已结束（${run.conclusion || 'unknown'}）`;
}

function statusClass(run) {
  if (!run || run.status !== 'completed') return 'status-warn';
  if (run.conclusion === 'success') return 'status-ok';
  return run.conclusion === 'skipped' ? '' : 'status-error';
}

function stepIcon(status, conclusion) {
  if (status !== 'completed') return '⏳';
  if (conclusion === 'success') return '✅';
  if (conclusion === 'skipped') return '⏭';
  return '❌';
}

function formatDuration(startedAt, completedAt) {
  if (!startedAt || !completedAt) return '';
  const secs = Math.round((new Date(completedAt) - new Date(startedAt)) / 1000);
  if (secs < 60) return `${secs}s`;
  return `${Math.floor(secs / 60)}m ${secs % 60}s`;
}

function renderJobsSummary(jobs) {
  const wrapper = document.createElement('div');
  wrapper.className = 'jobs-summary';

  jobs.forEach((job) => {
    const details = document.createElement('details');
    details.className = `job-entry ${statusClass(job)}`;

    const dur = formatDuration(job.started_at, job.completed_at);
    const summary = document.createElement('summary');
    summary.textContent = `${stepIcon(job.status, job.conclusion)} ${job.name}${dur ? ` (${dur})` : ''}`;
    details.appendChild(summary);

    const steps = (job.steps || []).filter((s) => s.name !== 'Set up job' && s.name !== 'Complete job');
    if (steps.length) {
      const list = document.createElement('ul');
      list.className = 'step-list';
      steps.forEach((step) => {
        const li = document.createElement('li');
        const stepDur = formatDuration(step.started_at, step.completed_at);
        li.textContent = `${stepIcon(step.status, step.conclusion)} ${step.name}${stepDur ? ` (${stepDur})` : ''}`;
        list.appendChild(li);
      });
      details.appendChild(list);
    }

    wrapper.appendChild(details);
  });

  return wrapper;
}

function attachLogViewerButton(card, runId) {
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'secondary log-btn';
  btn.textContent = '展开日志摘要';

  let summaryNode = null;
  btn.addEventListener('click', async () => {
    if (summaryNode) {
      summaryNode.hidden = !summaryNode.hidden;
      btn.textContent = summaryNode.hidden ? '展开日志摘要' : '收起日志摘要';
      return;
    }

    btn.textContent = '加载中…';
    btn.disabled = true;
    try {
      const payload = await githubFetch(`/repos/${state.owner}/${state.repo}/actions/runs/${runId}/jobs`);
      summaryNode = renderJobsSummary(payload.jobs || []);
      card.appendChild(summaryNode);
      btn.textContent = '收起日志摘要';
    } catch (err) {
      btn.textContent = `加载失败: ${err.message}`;
    } finally {
      btn.disabled = false;
    }
  });

  return btn;
}

function buildCard(issue, run) {
  const card = document.createElement('article');
  card.className = `run-card ${statusClass(run)}`;

  const header = document.createElement('header');
  const heading = document.createElement('h3');
  heading.textContent = `#${issue.number} · ${runStatusLabel(run)}`;
  const time = document.createElement('span');
  time.textContent = new Date(issue.created_at).toLocaleString();
  header.append(heading, time);
  card.appendChild(header);

  const titleP = document.createElement('p');
  titleP.textContent = issue.title;
  card.appendChild(titleP);

  const metaP = document.createElement('p');
  metaP.className = 'muted';
  metaP.textContent = `提交人：${issue.user?.login || 'unknown'} · Issue ${issue.state === 'open' ? '未关闭' : '已关闭'}`;
  card.appendChild(metaP);

  const linksP = document.createElement('p');
  linksP.append(makeLink(issue.html_url, '查看 Issue（下载链接在评论中）'));
  if (run) {
    linksP.append(' · ', makeLink(run.html_url, '查看 Actions 运行'));
  }
  card.appendChild(linksP);

  if (run) {
    card.appendChild(attachLogViewerButton(card, run.id));
  }

  return card;
}

async function refreshBuilds() {
  if (state.refreshHandle) {
    window.clearTimeout(state.refreshHandle);
    state.refreshHandle = null;
  }
  if (!state.owner || !state.repo) {
    return;
  }

  refreshButton.disabled = true;
  try {
    const [issues, runsPayload] = await Promise.all([
      githubFetch(`/repos/${state.owner}/${state.repo}/issues?state=all&sort=created&direction=desc&per_page=50`),
      githubFetch(`/repos/${state.owner}/${state.repo}/actions/workflows/build.yml/runs?event=issues&per_page=50`),
    ]);

    // Run titles look like "#12 [build] linux/x86_64 n7.1" (see run-name in build.yml).
    const runsByIssue = new Map();
    (runsPayload.workflow_runs || []).forEach((run) => {
      const match = (run.display_title || '').match(/^#(\d+) /);
      if (match && !runsByIssue.has(Number(match[1]))) {
        runsByIssue.set(Number(match[1]), run);
      }
    });

    const builds = (issues || [])
      .filter((issue) => !issue.pull_request && issue.title.startsWith(BUILD_TITLE_PREFIX))
      .slice(0, 20);

    buildListNode.className = buildListNode.dataset.baseClass;
    buildListNode.innerHTML = '';
    if (!builds.length) {
      setMessage(buildListNode, 'empty', '还没有编译记录。');
      return;
    }

    builds.forEach((issue) => {
      buildListNode.appendChild(buildCard(issue, runsByIssue.get(issue.number)));
    });

    const inProgress = builds.some((issue) => {
      const run = runsByIssue.get(issue.number);
      return issue.state === 'open' && (!run || run.status !== 'completed');
    });
    if (inProgress) {
      state.refreshHandle = window.setTimeout(refreshBuilds, AUTO_REFRESH_MS);
    }
  } catch (error) {
    setMessage(buildListNode, 'empty status-error', error.message);
  } finally {
    refreshButton.disabled = false;
  }
}

// ── Init ────────────────────────────────────────────────────────────────────

Object.assign(state, detectRepository());
formMessageNode.dataset.baseClass = 'form-message';
buildListNode.dataset.baseClass = 'run-list';

targetPlatformSelect.addEventListener('change', () => {
  updateArchOptions();
  syncConfigUI(); // platform-specific components (e.g. https) may change availability
});
updateArchOptions();

renderConfigControls();
state.config = loadSavedConfig();
syncConfigUI();
customOptionsInput.addEventListener('input', () => {
  const clean = sanitizeCustom(customOptionsInput.value);
  if (clean !== customOptionsInput.value) {
    // Drop disallowed characters as they are typed, keeping the caret in place.
    const caret = customOptionsInput.selectionStart - (customOptionsInput.value.length - clean.length);
    customOptionsInput.value = clean;
    customOptionsInput.setSelectionRange(caret, caret);
  }
  updateConfig({ custom: clean });
});
copyConfigButton.addEventListener('click', copyConfigure);
resetConfigButton.addEventListener('click', () => {
  state.config = defaultConfig();
  saveConfig();
  syncConfigUI();
  toggleNoticeNode.textContent = '';
});

form.addEventListener('submit', handleSubmit);
refreshButton.addEventListener('click', refreshBuilds);

loadRepositoryInfo();
refreshBuilds();
