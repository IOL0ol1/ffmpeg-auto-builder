import {
  DEFAULT_CONFIG, EXTRAS, LICENSES, LINKAGES, PRESETS, SAFE_TOKEN_PATTERN, buildConfigure,
} from './configure.js';

const form = document.querySelector('#build-form');
const presetSelect = document.querySelector('#preset');
const presetDescriptionNode = document.querySelector('#preset-description');
const linkageOptionsNode = document.querySelector('#linkage-options');
const licenseOptionsNode = document.querySelector('#license-options');
const extraOptionsNode = document.querySelector('#extra-options');
const customOptionsInput = document.querySelector('#custom-options');
const configurePreviewNode = document.querySelector('#configure-preview');
const configWarningsNode = document.querySelector('#config-warnings');
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

const state = {
  owner: '',
  repo: '',
  refreshHandle: null,
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

function renderChoices(container, items, type, name) {
  container.replaceChildren(...items.map((item) => {
    const label = document.createElement('label');
    label.className = 'choice';
    const input = document.createElement('input');
    input.type = type;
    input.name = name;
    input.value = item.id;
    const text = document.createElement('span');
    text.textContent = item.label;
    label.title = item.flags.join(' ') || '（不添加参数）';
    label.append(input, text);
    return label;
  }));
}

function renderConfigControls() {
  presetSelect.replaceChildren(...PRESETS.map((preset) => {
    const opt = document.createElement('option');
    opt.value = preset.id;
    opt.textContent = preset.label;
    return opt;
  }));
  renderChoices(linkageOptionsNode, LINKAGES, 'radio', 'linkage');
  renderChoices(licenseOptionsNode, LICENSES, 'radio', 'license');
  renderChoices(extraOptionsNode, EXTRAS, 'checkbox', 'extra');
}

function applyConfig(config) {
  presetSelect.value = config.preset;
  form.querySelectorAll('input[name="linkage"]').forEach((input) => { input.checked = input.value === config.linkage; });
  form.querySelectorAll('input[name="license"]').forEach((input) => { input.checked = input.value === config.license; });
  form.querySelectorAll('input[name="extra"]').forEach((input) => { input.checked = config.extras.includes(input.value); });
  customOptionsInput.value = config.custom;
}

function readConfig() {
  return {
    preset: presetSelect.value,
    linkage: form.querySelector('input[name="linkage"]:checked')?.value || DEFAULT_CONFIG.linkage,
    license: form.querySelector('input[name="license"]:checked')?.value || DEFAULT_CONFIG.license,
    extras: [...form.querySelectorAll('input[name="extra"]:checked')].map((input) => input.value),
    custom: customOptionsInput.value,
  };
}

function updateConfigurePreview() {
  const { options, warnings } = buildConfigure(readConfig());
  presetDescriptionNode.textContent = PRESETS.find((preset) => preset.id === presetSelect.value)?.description || '';
  configurePreviewNode.textContent = options;
  configWarningsNode.replaceChildren(...warnings.map((warning) => {
    const li = document.createElement('li');
    li.className = warning.level === 'error' ? 'status-error' : 'status-warn';
    li.textContent = warning.text;
    return li;
  }));
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
    configureOptions: buildConfigure(readConfig()).options,
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
  const unsafe = params.configureOptions.split(' ').find((token) => !SAFE_TOKEN_PATTERN.test(token));
  if (unsafe) {
    return `自定义参数含有不允许的字符：${unsafe}`;
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

targetPlatformSelect.addEventListener('change', updateArchOptions);
updateArchOptions();

renderConfigControls();
applyConfig(DEFAULT_CONFIG);
updateConfigurePreview();
form.querySelector('.config').addEventListener('input', updateConfigurePreview);
form.querySelector('.config').addEventListener('change', updateConfigurePreview);
resetConfigButton.addEventListener('click', () => {
  applyConfig(DEFAULT_CONFIG);
  updateConfigurePreview();
});

form.addEventListener('submit', handleSubmit);
refreshButton.addEventListener('click', refreshBuilds);

loadRepositoryInfo();
refreshBuilds();
